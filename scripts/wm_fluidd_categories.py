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
  * Categories are created only when missing (matched by name, ignoring case). Existing ones are kept.

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

# (category name, colour, exact macro names, name prefixes). The first rule that matches wins.
CATEGORIES = [
    ("Timelapse", "#00bcd4", ["GET_TIMELAPSE_SETUP", "HYPERLAPSE", "TIMELAPSE_RENDER", "TIMELAPSE_TAKE_FRAME", "TEST_STREAM_DELAY"], []),
    ("AcePro", "#f44336", ["WM_SET_TOOL_MAP"], ["ACE_", "WM_ENDLESS_", "WM_STATS_"]),
    ("Raspberry Pi", "#2196f3", [], ["WM_"]),
    ("WM Ultra Calibration", "#ffeb3b",
     ["G29", "PROBE_CALIBRATE", "BED_MESH_CALIBRATE", "CALIBRATE_OFFSET_ALL_RAPID_MODE", "CALIBRATE_OFFSET_ALL_FINE_MODE",
      "RAPID_MODE", "NOZZLE_PREPARE", "NOZZLE_CALIBRATE_TOOL_OFFSET", "CALIBRATE_TOOL_OFFSET", "CALIBRATE_TOOL_Z_OFFSET",
      "CALIBRATE_TOOL_POSITION", "GET_TOOL_POSITION", "CALIBRATE_WIPE_POSITION", "SAVE_TOOL_OFFSET", "SAVE_T_OFFSET",
      "SAVE_T_POSITON", "RESPOND_T_OFFSET", "RESPOND_T_POSITION"], []),
    ("WM Ultra Tool Change", "#4caf50",
     ["T0", "T1", "T2", "T3", "LOCK", "UNLOCK", "UNLOCK_TOOL_FINISH", "PARK_CURRENT_TOOL", "PARK_CURRENT_TOOL_RETRY", "Z_HOMING"], []),
    ("WM Ultra Filament", "#ff9800",
     ["LOAD_FILAMENT", "UNLOAD_FILAMENT", "EXTRUDE_FILAMENT", "RETRACT_FILAMENT", "filament_insert", "filament_insert_gcode",
      "POP", "E_axis_move", "RESET_FLOW_EXTRUDER", "WIPE_NOZZLE", "WIPE_NOZZLE_SIMPLE", "WIPE_NOZZ"], []),
    ("ZR Tools", "#9c27b0", [], ["ZR_"]),
    ("WM Ultra Print", "#9e9e9e", ["START_PRINT", "PRINT_END", "CANCEL_PRINT", "PAUSE", "RESUME", "G30", "G31"], []),
    ("WM Ultra Tests", "#607d8b", [], ["TEST_"]),
]
# Shown in this order in Fluidd (the order the categories are created in).
CATEGORY_ORDER = ["Raspberry Pi", "AcePro", "WM Ultra Calibration", "WM Ultra Tool Change", "WM Ultra Filament",
                  "ZR Tools", "WM Ultra Print", "WM Ultra Tests", "Timelapse"]
# Helper macros nobody presses by hand: hidden the first time they are seen.
HIDDEN = ["M104", "M106", "M107", "M109", "M141", "M190", "M191", "M221", "z_rise"]

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
    report = {"categorized": 0, "hidden": 0, "kept": 0, "created": created}
    new_handled = list(handled)
    seq = 0

    def ensure_category(name):
        nonlocal seq
        if name.lower() not in cat_id:
            seq += 1
            cid = str(now_ms + seq)
            cats.append({"id": cid, "name": name})
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
            report["categorized"] += 1
    report["changed"] = bool(created or report["categorized"] or report["hidden"] or len(new_handled) != len(handled))
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
