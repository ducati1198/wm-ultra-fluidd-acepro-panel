#!/usr/bin/env python3
"""Sorts the macros of a WonderMaker printer into Fluidd's macro categories (names and colours below).

Fluidd keeps its macro list in Moonraker's database (namespace "fluidd", key "macros"), so this talks to
Moonraker and changes nothing on disk except the backup file it is asked to write.

Rules that keep the user's own choices safe:
  * A macro is sorted only if its Fluidd entry is still the default one (visible, no category, no colour,
    no alias). A macro you moved, recoloured, renamed or hid yourself is left alone.
  * Every macro is dealt with once. Its name is then recorded in Moonraker's database (namespace "wm_ultra",
    key "fluidd_categories"), so a macro you later move back or unhide is never touched again. Macros added
    by a later update are new, so they are sorted the first time they are seen.
  * Categories are created only when missing (matched by name, ignoring case). Existing ones are kept. A new one
    is placed after the category that comes before it in the list below, when that one exists.
  * The offset and Z calibration macros were in "Raspberry Pi" up to 1.7.9. They are moved to "Offset Calibration"
    once, and only while their entry is still what the installer wrote. One you moved or recoloured stays.
  * One colour per category, and every category its own colour (table CATEGORIES). A macro in one of these categories
    whose colour is still one the installer writes (or none) gets its category's colour; a colour you picked stays.
  * 1.10.0 layout: WonderMaker's own calibration macros are in "WM Factory Calibration" (the category "WM Ultra
    Calibration" is renamed once, keeping its macros). Every calibration macro of the Pi installer is in "RPI Calibration"
    (1.16.2: shown with the real macro name, no alias any more); "Offset Calibration" is emptied into it and removed when empty.
    The unload window (Unload Menu, Unload Stop) is in "WM Ultra Filament", Nozzle Change and Chamber Light in "ZR Tools";
    "Raspberry Pi" is removed when empty. SET_GCODE_OFFSET, Z_OFFSET_APPLY_ENDSTOP,
    Z_OFFSET_APPLY_PROBE and WM_BED_SOAK are hidden (buttons and switches call them). Each of these moves happens once
    and only for an entry still as the installer wrote it.

Usage:
  wm_fluidd_categories.py apply [--url URL] [--wait SECONDS] [--backup FILE] [--dry-run]
Exit codes: 0 done (or nothing to do), 2 Moonraker or Klipper could not be reached in time, 1 any other problem.
"""
import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# The Pi installer's tool offset and Z calibration macros (their own category up to 1.9.x, part of RPI Calibration since 1.10.0).
OFFSET_MACROS = ["WM_FULL_OFFSET_CAL", "WM_OFFSETS_ACCURATE", "WM_OFFSETS_RAPID", "WM_SETTER_PROBE_POSITION", "WM_OFFSETS_Z_HOT", "WM_NOZZLE_GROWTH_CAL",
                 "WM_NOZZLE_GROWTH", "WM_Z_TRIM", "WM_Z_TRIM_MENU", "WM_PROBE_CALIBRATE"]
# Every calibration macro of the Pi installer (1.10.0): one category, "RPI Calibration".
RPI_CAL_MACROS = OFFSET_MACROS + ["WM_FIRST_RUN_CAL", "WM_CAL_HELP", "WM_BED_LEVELING", "WM_SCREWS_CAL", "WM_BED_PID",
                                  "WM_NOZZLE_FULL_PID", "WM_VIBRATION_COMP", "WM_LIVE_Z_MENU", "WM_LIVE_Z_ZERO", "WM_BED_SOAK_MENU",
                                  "WM_BED_WARP_MEASURE", "WM_BED_WARP_STOP", "WM_AUTO_SPEED", "WM_AUTO_SPEED_VALIDATE",
                                  "WM_EXTRUDER_SETUP"]
UNLOAD_MACROS = ["WM_UNLOAD_MENU", "WM_UNLOAD_STOP"]
# Windows opened from the Toolheads card and the touchscreen (1.17.0): purge, load, resume with another tool. Same category as the unload window.
FILAMENT_MENUS = ["WM_PURGE_MENU", "WM_LOAD_MENU", "WM_RESUME_TOOL"]
# The Pi installer's printer tools that are not calibration: with WonderMaker's ZR tools (1.10.0; there is no
# "Raspberry Pi" category any more). A WM_ macro that is in none of these lists stays uncategorized.
ZR_PI_MACROS = ["WM_NOZZLE_CHANGE", "WM_CHAMBER_LIGHT"]
FACTORY_CAL = ["G29", "PROBE_CALIBRATE", "BED_MESH_CALIBRATE", "CALIBRATE_OFFSET_ALL_RAPID_MODE", "CALIBRATE_OFFSET_ALL_FINE_MODE",
               "RAPID_MODE", "NOZZLE_PREPARE", "NOZZLE_CALIBRATE_TOOL_OFFSET", "CALIBRATE_TOOL_OFFSET", "CALIBRATE_TOOL_Z_OFFSET",
               "CALIBRATE_TOOL_POSITION", "GET_TOOL_POSITION", "CALIBRATE_WIPE_POSITION", "SAVE_TOOL_OFFSET", "SAVE_T_OFFSET",
               "SAVE_T_POSITON", "RESPOND_T_OFFSET", "RESPOND_T_POSITION"]
# (category name, colour, exact macro names, name prefixes). The first rule that matches wins (rule order, not display order).
CATEGORIES = [
    ("Timelapse", "#00bcd4", ["GET_TIMELAPSE_SETUP", "HYPERLAPSE", "TIMELAPSE_RENDER", "TIMELAPSE_TAKE_FRAME", "TEST_STREAM_DELAY"], []),
    ("AcePro", "#f44336", ["WM_SET_TOOL_MAP"], ["ACE_", "WM_ENDLESS_", "WM_STATS_"]),
    ("RPI Calibration", "#e91e63", RPI_CAL_MACROS, []),
    ("WM Ultra Filament", "#ff9800",
     ["LOAD_FILAMENT", "UNLOAD_FILAMENT", "EXTRUDE_FILAMENT", "RETRACT_FILAMENT", "filament_insert", "filament_insert_gcode",
      "POP", "E_axis_move", "RESET_FLOW_EXTRUDER", "WIPE_NOZZLE", "WIPE_NOZZ"] + UNLOAD_MACROS + FILAMENT_MENUS, []),
    ("WM Factory Calibration", "#ffeb3b", FACTORY_CAL, []),
    ("WM Ultra Tool Change", "#4caf50",
     ["T0", "T1", "T2", "T3", "LOCK", "UNLOCK", "UNLOCK_TOOL_FINISH", "PARK_CURRENT_TOOL", "PARK_CURRENT_TOOL_RETRY", "Z_HOMING"], []),
    ("ZR Tools", "#9c27b0", ZR_PI_MACROS, ["ZR_"]),
    ("WM Ultra Print", "#9e9e9e", ["START_PRINT", "PRINT_END", "CANCEL_PRINT", "PAUSE", "RESUME", "G30", "G31"], []),
    ("WM Ultra Tests", "#607d8b", [], ["TEST_"]),
]
# Shown in this order in Fluidd (the order the categories are created in). "Raspberry Pi" is only there for placement:
# no macro goes into it any more, but on an update it can still exist while you keep a macro of your own in it.
CATEGORY_ORDER = ["Raspberry Pi", "RPI Calibration", "Offset Calibration", "AcePro", "WM Factory Calibration", "WM Ultra Tool Change",
                  "WM Ultra Filament", "ZR Tools", "WM Ultra Print", "WM Ultra Tests", "Timelapse"]
# Helper macros nobody presses by hand: hidden the first time they are seen.
HIDDEN = ["M104", "M106", "M107", "M109", "M141", "M190", "M191", "M221", "z_rise",
          "SET_GCODE_OFFSET", "Z_OFFSET_APPLY_ENDSTOP", "Z_OFFSET_APPLY_PROBE", "WM_BED_SOAK"]
# 1.16.2: no aliases are written any more, Fluidd shows the real macro names. These are the aliases that 1.10.0 to 1.16.1 wrote:
# they are cleared once, and only while the entry still holds exactly this alias (one you typed yourself stays).
ALIASES = {}
OLD_ALIASES = {
    "WM_FIRST_RUN_CAL": "First Run Calibration", "WM_CAL_HELP": "Calibration Help", "WM_BED_LEVELING": "Bed Leveling",
    "WM_SCREWS_CAL": "Bed Screws", "WM_BED_PID": "Bed PID", "WM_NOZZLE_TEMP_CAL": "Nozzle PID", "WM_VIBRATION_COMP": "Input Shaper",
    "WM_FULL_OFFSET_CAL": "Full Offset Calibration", "WM_OFFSETS_RAPID": "Offsets Rapid", "WM_SETTER_PROBE_POSITION": "Tool Setter Position", "WM_OFFSETS_ACCURATE": "Offsets Accurate",
    "WM_OFFSETS_Z_HOT": "Z Offsets Hot", "WM_PROBE_CALIBRATE": "Probe Calibrate", "WM_NOZZLE_GROWTH_CAL": "Nozzle Growth Calibration",
    "WM_NOZZLE_GROWTH": "Nozzle Growth Value", "WM_Z_TRIM_MENU": "Z Trim Menu", "WM_Z_TRIM": "Z Trim", "WM_LIVE_Z_MENU": "Live Z Menu",
    "WM_LIVE_Z_ZERO": "Live Z Zero", "WM_BED_SOAK_MENU": "Bed Warp Wait", "WM_BED_WARP_MEASURE": "Measure Bed Warp",
    "WM_BED_WARP_STOP": "Stop Bed Warp Measure", "WM_AUTO_SPEED": "Speed Test", "WM_AUTO_SPEED_VALIDATE": "Speed Check",
    "WM_UNLOAD_MENU": "Unload Menu", "WM_UNLOAD_STOP": "Unload Stop", "WM_EXTRUDER_SETUP": "Extruder Setup",
    "WM_NOZZLE_CHANGE": "Nozzle Change", "WM_CHAMBER_LIGHT": "Chamber Light",
}
# Categories an earlier version created under another name: renamed once (id and macros kept), when the new name is not there yet.
RENAMES = [("WM Ultra Calibration", "WM Factory Calibration")]
RENAME_MARK = "renamed:"
# Categories an earlier version created that this version no longer uses: removed once, only when no macro is left in them.
RETIRED = ["Offset Calibration", "Raspberry Pi"]
RETIRED_MARK = "removed:"

# Macros an earlier version sorted into another category. They are moved once (to where match() puts them now, with
# the readable name), and only while their entry is still exactly what that version wrote (one of the old category +
# colour pairs, visible, no alias): (macro names, [(old category, old colour)], mark).
MOVES = [(OFFSET_MACROS, [("Raspberry Pi", "#2196f3")], "moved:"),
         (RPI_CAL_MACROS + UNLOAD_MACROS + ZR_PI_MACROS + ["WM_BED_SOAK"], [("Raspberry Pi", "#2196f3"), ("Offset Calibration", "#e91e63")], "moved110:")]
# Colours earlier versions wrote for categories that are gone (they count as installer colours, not yours).
OLD_COLOURS = ["#2196f3"]
MOVED_MARK = "moved:"      # "moved:<name>" in the handled list = this macro's move was dealt with (a macro name has no colon)

NS_FLUIDD, KEY_MACROS = "fluidd", "macros"
NS_OURS, KEY_HANDLED = "wm_ultra", "fluidd_categories"


class Unreachable(Exception):
    pass


def match(name):
    """-> ("category", colour) | ("hide", None) | None"""
    low = name.lower()
    if low in [h.lower() for h in HIDDEN]:
        return ("hide", None)
    for cat, colour, names, prefixes in CATEGORIES:
        if low in [n.lower() for n in names] or any(low.startswith(p.lower()) for p in prefixes):
            return (cat, colour)
    return None


def pristine(entry):
    return (entry.get("visible", True) is True and not entry.get("color") and not entry.get("alias")
            and str(entry.get("categoryId", "0")) in ("0", "", "None")
            and not entry.get("disabledWhilePrinting", False))


def plan(macros, fluidd_value, handled, now_ms=None):
    """Pure function. Returns (new_fluidd_value, new_handled_list, report)."""
    now_ms = int(time.time() * 1000) if now_ms is None else now_ms
    value = json.loads(json.dumps(fluidd_value)) if isinstance(fluidd_value, dict) else {}
    stored = value.setdefault("stored", [])
    cats = value.setdefault("categories", [])
    expanded = value.setdefault("expanded", [0])
    done = {h.lower() for h in handled}
    by_name = {m.get("name", "").lower(): m for m in stored}
    cat_id = {c.get("name", "").lower(): c.get("id") for c in cats}
    created = []
    report = {"categorized": 0, "hidden": 0, "kept": 0, "moved": 0, "created": created}
    new_handled = list(handled)
    seq = 0
    for old_name, new_name in RENAMES:
        mark = RENAME_MARK + old_name
        if mark.lower() in done:
            continue
        old_c = next((c for c in cats if c.get("name", "").lower() == old_name.lower()), None)
        if old_c is not None and new_name.lower() not in cat_id:
            old_c["name"] = new_name
            cat_id[new_name.lower()] = cat_id.pop(old_name.lower())
            report.setdefault("renamed", []).append("%s -> %s" % (old_name, new_name))
        new_handled.append(mark)

    def ensure_category(name):
        nonlocal seq
        if name.lower() not in cat_id:
            seq += 1
            cid = str(now_ms + seq)
            # after the nearest category that comes before it in CATEGORY_ORDER; at the end when none of those exists
            pos = len(cats)
            before = [n.lower() for n in CATEGORY_ORDER[:CATEGORY_ORDER.index(name)]] if name in CATEGORY_ORDER else []
            for i, c in enumerate(cats):
                if c.get("name", "").lower() in before:
                    pos = i + 1
            cats.insert(pos, {"id": cid, "name": name})
            cat_id[name.lower()] = cid
            expanded.append(len(cats) - 1)
            created.append(name)
        return cat_id[name.lower()]

    wanted = {}
    for name in macros:
        if name.startswith("_") or name.lower() in done:
            continue
        r = match(name)
        if r:
            wanted[name] = r
    # create the categories in the order Fluidd should list them
    for cname in CATEGORY_ORDER:
        if any(r[0] == cname for r in wanted.values()):
            ensure_category(cname)
    for name, (kind, colour) in sorted(wanted.items(), key=lambda kv: kv[0].lower()):
        entry = by_name.get(name.lower())
        new_handled.append(name)
        for names, _, mark in MOVES:
            if name.lower() in [n.lower() for n in names]:
                new_handled.append(mark + name)       # sorted by this version: there is nothing to move later
        if entry is not None and not pristine(entry):
            report["kept"] += 1          # you changed it yourself (or it is already hidden): left as it is
            continue
        if entry is None:
            entry = {"name": name, "alias": "", "visible": True, "disabledWhilePrinting": False, "color": "", "categoryId": "0"}
            stored.append(entry)
            by_name[name.lower()] = entry
        if kind == "hide":
            entry["visible"] = False
            report["hidden"] += 1
        else:
            entry["categoryId"] = ensure_category(kind)
            entry["color"] = colour
            entry["alias"] = ALIASES.get(name, "")
            report["categorized"] += 1
    # one-time moves of macros an earlier version sorted elsewhere
    for names, olds, mark_prefix in MOVES:
        for name in names:
            mark = mark_prefix + name
            entry = by_name.get(name.lower())
            if mark.lower() in done or mark in new_handled or name.lower() not in done or entry is None or name not in macros:
                continue                      # already dealt with, or sorted by this version (so it is in the right place)
            new_handled.append(mark)
            r = match(name)
            here = [oc for oc, ocol in olds if oc.lower() in cat_id and str(entry.get("categoryId")) == str(cat_id[oc.lower()])
                    and entry.get("color") == ocol]
            if not r or not here or entry.get("visible", True) is not True or entry.get("alias") or r[0] == here[0]:
                continue
            if r[0] == "hide":
                entry["visible"] = False
                entry["categoryId"] = "0"
                entry["color"] = ""
            else:
                entry["categoryId"] = ensure_category(r[0])
                entry["color"] = r[1]
                entry["alias"] = ALIASES.get(name, "")
            report["moved"] += 1
    # 1.16.2: the readable names written by 1.10.0 to 1.16.1 are cleared once (Fluidd then shows the real macro name)
    for name, old_alias in OLD_ALIASES.items():
        mark = "noalias:" + name
        entry = by_name.get(name.lower())
        if mark.lower() in done or mark in new_handled or entry is None or name not in macros:
            continue
        new_handled.append(mark)
        if entry.get("alias") == old_alias:
            entry["alias"] = ""
            report["unaliased"] = report.get("unaliased", 0) + 1
    # one colour per category: a macro in one of our categories gets that category's colour, unless you gave it your own
    ours = {c.lower(): col for c, col, _, _ in CATEGORIES}
    installer_colours = {col.lower() for col in ours.values()} | {c.lower() for c in OLD_COLOURS} | {""}
    names_by_id = {str(c.get("id")): c.get("name", "").lower() for c in cats}
    for m in stored:
        cname = names_by_id.get(str(m.get("categoryId")))
        want = ours.get(cname) if cname else None
        if want and (m.get("color") or "").lower() != want.lower() and (m.get("color") or "").lower() in installer_colours:
            m["color"] = want
            report["recoloured"] = report.get("recoloured", 0) + 1
    # categories this version no longer uses: removed once, when empty
    for cname in RETIRED:
        mark = RETIRED_MARK + cname
        cid = cat_id.get(cname.lower())
        if cid is None or mark.lower() in done or mark in new_handled:
            continue
        if any(str(m.get("categoryId")) == str(cid) for m in stored):
            continue                          # you still keep macros there: the category stays
        new_handled.append(mark)
        pos = next(i for i, c in enumerate(cats) if str(c.get("id")) == str(cid))
        del cats[pos]
        del cat_id[cname.lower()]
        value["expanded"] = [e - 1 if e > pos else e for e in expanded if e != pos]
        expanded = value["expanded"]
        report.setdefault("removed", []).append(cname)
    report["changed"] = bool(created or report["categorized"] or report["hidden"] or report["moved"] or report.get("renamed") or report.get("recoloured") or report.get("unaliased")
                             or report.get("removed") or len(new_handled) != len(handled))
    return value, new_handled, report


def call(url, path, data=None, timeout=8):
    req = urllib.request.Request(url.rstrip("/") + path, method="POST" if data is not None else "GET",
                                 data=json.dumps(data).encode() if data is not None else None,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode() or "{}")


def db_get(url, ns, key):
    try:
        return call(url, "/server/database/item?" + urllib.parse.urlencode({"namespace": ns, "key": key}))["result"]["value"]
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def db_set(url, ns, key, value):
    call(url, "/server/database/item", {"namespace": ns, "key": key, "value": value})


def macro_names(url, wait):
    """The macros Klipper has loaded. Waits up to `wait` seconds for Klipper to be ready."""
    end, last = time.time() + wait, "Moonraker did not answer"
    while True:
        try:
            state = call(url, "/printer/info")["result"]["state"]
            if state == "ready":
                objs = call(url, "/printer/objects/list")["result"]["objects"]
                return [o[len("gcode_macro "):] for o in objs if o.startswith("gcode_macro ")]
            last = "Klipper is %s" % state
        except (urllib.error.URLError, OSError, KeyError, ValueError) as e:
            last = "Moonraker did not answer (%s)" % getattr(e, "reason", e)
        if time.time() >= end:
            raise Unreachable(last)
        time.sleep(3)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("action", choices=["apply"])
    ap.add_argument("--url", default="http://127.0.0.1:7125")
    ap.add_argument("--wait", type=int, default=0)
    ap.add_argument("--backup")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)
    try:
        macros = macro_names(a.url, a.wait)
        value = db_get(a.url, NS_FLUIDD, KEY_MACROS)
        ours = db_get(a.url, NS_OURS, KEY_HANDLED) or {}
        handled = ours.get("handled", []) if isinstance(ours, dict) else []
        new_value, new_handled, rep = plan(macros, value, handled)
        if not rep["changed"]:
            print("Fluidd macros: nothing new to sort.")
            return 0
        msg = "Fluidd macros: %d sorted into categories, %d hidden, %d left as you set them" % (rep["categorized"], rep["hidden"], rep["kept"])
        if rep["moved"]:
            msg += ", %d moved to their new category" % rep["moved"]
        if rep.get("recoloured"):
            msg += ", %d recoloured to their category's colour" % rep["recoloured"]
        if rep.get("renamed"):
            msg += "; renamed: " + ", ".join(rep["renamed"])
        if rep.get("removed"):
            msg += "; removed empty: " + ", ".join(rep["removed"])
        if rep["created"]:
            msg += "; new categories: " + ", ".join(rep["created"])
        if a.dry_run:
            print(msg + " (dry run, nothing written)")
            return 0
        if a.backup:
            with open(a.backup, "w") as f:
                json.dump({"fluidd_macros": value, "wm_ultra_handled": handled}, f, indent=1)
        db_set(a.url, NS_FLUIDD, KEY_MACROS, new_value)
        db_set(a.url, NS_OURS, KEY_HANDLED, {"handled": new_handled})
        print(msg + ".")
        return 0
    except Unreachable as e:
        print("Fluidd macros: not done (%s)." % e)
        return 2
    except (urllib.error.URLError, OSError, ValueError, KeyError) as e:
        print("Fluidd macros: not done (%s)." % e)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
