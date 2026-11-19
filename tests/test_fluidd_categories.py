"""Tests of scripts/wm_fluidd_categories.py: the rules, the "never touch what the user changed" behaviour,
and the whole thing against a fake Moonraker on localhost.
Run:  python3 -I tests/test_fluidd_categories.py      (no packages needed)"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "scripts", "wm_fluidd_categories.py")
spec = importlib.util.spec_from_file_location("wmfc", SCRIPT)
wmfc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wmfc)

FAILED = []


def check(name, cond):
    print(("  ok    " if cond else "  FAIL  ") + name)
    if not cond:
        FAILED.append(name)


def entry(name, **kw):
    e = {"name": name, "alias": "", "visible": True, "disabledWhilePrinting": False, "color": "", "categoryId": "0"}
    e.update(kw)
    return e


def cat_of(value, name):
    ids = {c["id"]: c["name"] for c in value["categories"]}
    for m in value["stored"]:
        if m["name"] == name:
            return ids.get(m["categoryId"], "-")
    return None


MACROS = ["ACE_WM_LOAD", "WM_ENDLESS_SET", "WM_STATS_RESET", "WM_SET_TOOL_MAP", "WM_BED_LEVELING", "WM_SCREWS_CAL", "WM_OFFSETS_RAPID", "WM_SETTER_PROBE_POSITION", "G29",
          "RAPID_MODE", "T0", "PARK_CURRENT_TOOL", "LOAD_FILAMENT", "WIPE_NOZZ", "ZR_LOAD", "START_PRINT", "TEST_XY",
          "TEST_STREAM_DELAY", "HYPERLAPSE", "M104", "z_rise", "_HIDDEN_HELPER", "SOMETHING_ELSE"]

print("rules")
v, h, r = wmfc.plan(MACROS, None, [], now_ms=1000)
check("AcePro: ACE_*, WM_ENDLESS_*, WM_STATS_*, WM_SET_TOOL_MAP", all(cat_of(v, n) == "AcePro" for n in ["ACE_WM_LOAD", "WM_ENDLESS_SET", "WM_STATS_RESET", "WM_SET_TOOL_MAP"]))
check("RPI Calibration: Tool Setter Position (WM_SETTER_PROBE_POSITION, 1.13.0) is there, pink, real name", cat_of(v, "WM_SETTER_PROBE_POSITION") == "RPI Calibration" and [(m["color"], m["alias"]) for m in v["stored"] if m["name"] == "WM_SETTER_PROBE_POSITION"] == [("#e91e63", "")])
check("RPI Calibration: the Pi's calibration macros, pink, with real macro names (no alias)", all(cat_of(v, n) == "RPI Calibration" for n in ["WM_BED_LEVELING", "WM_SCREWS_CAL", "WM_OFFSETS_RAPID"])
      and [m["color"] for m in v["stored"] if m["name"] == "WM_OFFSETS_RAPID"] == ["#e91e63"] and next(m for m in v["stored"] if m["name"] == "WM_BED_LEVELING")["alias"] == "")
check("WonderMaker factory macros land in their categories",
      cat_of(v, "G29") == "WM Factory Calibration" and cat_of(v, "RAPID_MODE") == "WM Factory Calibration" and cat_of(v, "T0") == "WM Ultra Tool Change"
      and cat_of(v, "PARK_CURRENT_TOOL") == "WM Ultra Tool Change" and cat_of(v, "LOAD_FILAMENT") == "WM Ultra Filament" and cat_of(v, "WIPE_NOZZ") == "WM Ultra Filament"
      and cat_of(v, "ZR_LOAD") == "ZR Tools" and cat_of(v, "START_PRINT") == "WM Ultra Print" and cat_of(v, "TEST_XY") == "WM Ultra Tests")
check("TEST_STREAM_DELAY goes to Timelapse, not Tests", cat_of(v, "TEST_STREAM_DELAY") == "Timelapse" and cat_of(v, "HYPERLAPSE") == "Timelapse")
check("colours", [m["color"] for m in v["stored"] if m["name"] == "ACE_WM_LOAD"] == ["#f44336"] and [m["color"] for m in v["stored"] if m["name"] == "WM_BED_LEVELING"] == ["#e91e63"]
      and [m["color"] for m in v["stored"] if m["name"] == "G29"] == ["#ffeb3b"])
check("helper macros are hidden, not categorized", all(next(m for m in v["stored"] if m["name"] == n)["visible"] is False and cat_of(v, n) == "-" for n in ["M104", "z_rise"]))
check("macros starting with _ and unknown macros are left out", not any(m["name"] in ("_HIDDEN_HELPER", "SOMETHING_ELSE") for m in v["stored"]))
check("categories are created in Fluidd's order, only the ones needed", [c["name"] for c in v["categories"]] == ["RPI Calibration", "AcePro", "WM Factory Calibration", "WM Ultra Tool Change", "WM Ultra Filament", "ZR Tools", "WM Ultra Print", "WM Ultra Tests", "Timelapse"])
check("new categories are expanded", v["expanded"] == [0, 0, 1, 2, 3, 4, 5, 6, 7, 8])
check("only the macros that exist are used (a printer without an ACE gets no AcePro category)", "AcePro" not in [c["name"] for c in wmfc.plan(["WM_BED_LEVELING", "G29"], None, [], now_ms=5)[0]["categories"]])
check("the report counts", r["categorized"] == 19 and r["hidden"] == 2 and r["kept"] == 0 and len(r["created"]) == 9)

print("never touch what the user changed")
mine = {"stored": [entry("G29", categoryId="77", color="#123456"), entry("WM_BED_LEVELING", alias="Level bed"), entry("ZR_LOAD", visible=False),
                   entry("START_PRINT", disabledWhilePrinting=True), entry("T1")],
        "categories": [{"id": "77", "name": "Mine"}], "expanded": [0]}
v2, h2, r2 = wmfc.plan(["G29", "WM_BED_LEVELING", "ZR_LOAD", "START_PRINT", "T1", "M104"], mine, [], now_ms=2000)
check("a macro in the user's own category keeps category and colour", cat_of(v2, "G29") == "Mine" and next(m for m in v2["stored"] if m["name"] == "G29")["color"] == "#123456")
check("a renamed macro keeps its alias and has no category added", next(m for m in v2["stored"] if m["name"] == "WM_BED_LEVELING")["alias"] == "Level bed" and cat_of(v2, "WM_BED_LEVELING") == "-")
check("a macro the user hid, or disabled while printing, is left as it is", next(m for m in v2["stored"] if m["name"] == "ZR_LOAD")["visible"] is False and cat_of(v2, "ZR_LOAD") == "-" and cat_of(v2, "START_PRINT") == "-")
check("an untouched macro is sorted", cat_of(v2, "T1") == "WM Ultra Tool Change")
check("the user's category stays, with its id", {"id": "77", "name": "Mine"} in v2["categories"])
check("a category the user already has (same name, any case) is reused, not duplicated", [c["id"] for c in wmfc.plan(["G29"], {"stored": [entry("G29")], "categories": [{"id": "9", "name": "wm ultra calibration"}], "expanded": [0]}, [], now_ms=3)[0]["categories"]] == ["9"])
check("the input is not modified", mine["stored"][0]["categoryId"] == "77" and len(mine["categories"]) == 1)

print("every macro is dealt with once")
v3, h3, r3 = wmfc.plan(MACROS, None, [], now_ms=1000)
for m in v3["stored"]:
    if m["name"] == "M104":
        m["visible"] = True               # the user unhides it
    if m["name"] == "G29":
        m["categoryId"] = "0"; m["color"] = ""   # and moves G29 out of its category
v4, h4, r4 = wmfc.plan(MACROS, v3, h3, now_ms=2000)
check("a second run changes nothing", not r4["changed"] and v4 == v3)
check("an unhidden macro stays visible, a moved macro stays uncategorized", next(m for m in v4["stored"] if m["name"] == "M104")["visible"] is True and cat_of(v4, "G29") == "-")
v5, h5, r5 = wmfc.plan(MACROS + ["ACE_WM_DRY_START", "TEST_FAN"], v3, h3, now_ms=3000)
check("macros added by a later update are sorted the first time they are seen", cat_of(v5, "ACE_WM_DRY_START") == "AcePro" and cat_of(v5, "TEST_FAN") == "WM Ultra Tests" and r5["categorized"] == 2)
check("handled names are remembered", set(h5) >= set(h3) | {"ACE_WM_DRY_START", "TEST_FAN"})

print("1.10.0 layout")
ALLO = wmfc.RPI_CAL_MACROS + ["WM_CHAMBER_LIGHT", "WM_NOZZLE_CHANGE", "WM_UNLOAD_MENU", "WM_UNLOAD_STOP", "WM_EXTRUDER_SETUP", "ACE_WM_LOAD", "G29",
                              "SET_GCODE_OFFSET", "Z_OFFSET_APPLY_PROBE", "Z_OFFSET_APPLY_ENDSTOP", "WM_BED_SOAK"]
vo, ho, ro = wmfc.plan(ALLO, None, [], now_ms=1000)
check("all 25 Pi calibration macros land in RPI Calibration, Extruder Setup too", all(cat_of(vo, n) == "RPI Calibration" for n in wmfc.RPI_CAL_MACROS) and len(wmfc.RPI_CAL_MACROS) == 25 and cat_of(vo, "WM_EXTRUDER_SETUP") == "RPI Calibration")
check("real macro names (no alias): Speed Test, Live Z Menu, Bed Warp Wait", [next(m for m in vo["stored"] if m["name"] == n)["alias"] for n in ["WM_AUTO_SPEED", "WM_LIVE_Z_MENU", "WM_BED_SOAK_MENU"]] == ["", "", ""])
check("Unload Menu and Unload Stop are in WM Ultra Filament", cat_of(vo, "WM_UNLOAD_MENU") == "WM Ultra Filament" and next(m for m in vo["stored"] if m["name"] == "WM_UNLOAD_MENU")["alias"] == "" and cat_of(vo, "WM_UNLOAD_STOP") == "WM Ultra Filament")
check("Chamber Light and Nozzle Change are in ZR Tools, purple, real names", all(cat_of(vo, n) == "ZR Tools" and next(m for m in vo["stored"] if m["name"] == n)["color"] == "#9c27b0" for n in ["WM_CHAMBER_LIGHT", "WM_NOZZLE_CHANGE"]) and next(m for m in vo["stored"] if m["name"] == "WM_CHAMBER_LIGHT")["alias"] == "")
check("the buttons' helpers are hidden: SET_GCODE_OFFSET, Z_OFFSET_APPLY_*, WM_BED_SOAK", all(next(m for m in vo["stored"] if m["name"] == n)["visible"] is False for n in ["SET_GCODE_OFFSET", "Z_OFFSET_APPLY_PROBE", "Z_OFFSET_APPLY_ENDSTOP", "WM_BED_SOAK"]))
check("RPI Calibration comes first; no Raspberry Pi and no Offset Calibration category", [c["name"] for c in vo["categories"]][:2] == ["RPI Calibration", "AcePro"] and not {"Raspberry Pi", "Offset Calibration"} & {c["name"] for c in vo["categories"]})
check("a fresh sort moves nothing afterwards", ro["moved"] == 0 and not wmfc.plan(ALLO, vo, ho, now_ms=2000)[2]["changed"])

# a printer sorted by 1.9.x: Offset Calibration (pink), Raspberry Pi (blue) with calibration, unload and WM_BED_SOAK, WM Ultra Calibration
old = {"stored": [entry("WM_OFFSETS_RAPID", categoryId="20", color="#e91e63"), entry("WM_Z_TRIM", categoryId="20", color="#e91e63"),
                  entry("WM_BED_LEVELING", categoryId="10", color="#2196f3"), entry("WM_AUTO_SPEED", categoryId="10", color="#2196f3"),
                  entry("WM_UNLOAD_MENU", categoryId="10", color="#2196f3"), entry("WM_BED_SOAK", categoryId="10", color="#2196f3"),
                  entry("WM_CHAMBER_LIGHT", categoryId="10", color="#2196f3"), entry("WM_SCREWS_CAL", categoryId="10", color="#00ff00"),
                  entry("G29", categoryId="30", color="#ffeb3b"), entry("ACE_WM_LOAD", categoryId="11", color="#f44336")],
       "categories": [{"id": "10", "name": "Raspberry Pi"}, {"id": "20", "name": "Offset Calibration"}, {"id": "11", "name": "AcePro"},
                      {"id": "30", "name": "WM Ultra Calibration"}], "expanded": [0, 0, 1, 2, 3]}
oldh = ["WM_OFFSETS_RAPID", "WM_Z_TRIM", "WM_BED_LEVELING", "WM_AUTO_SPEED", "WM_UNLOAD_MENU", "WM_BED_SOAK", "WM_CHAMBER_LIGHT", "WM_SCREWS_CAL",
        "G29", "ACE_WM_LOAD", "moved:WM_OFFSETS_RAPID", "moved:WM_Z_TRIM"]
om = ["WM_OFFSETS_RAPID", "WM_Z_TRIM", "WM_BED_LEVELING", "WM_AUTO_SPEED", "WM_UNLOAD_MENU", "WM_BED_SOAK", "WM_CHAMBER_LIGHT", "WM_SCREWS_CAL",
      "G29", "ACE_WM_LOAD", "WM_LIVE_Z_MENU"]
vm, hm, rm = wmfc.plan(om, old, oldh, now_ms=5000)
check("update from 1.9.x: WM Ultra Calibration is renamed WM Factory Calibration, same id, G29 stays in it",
      {"id": "30", "name": "WM Factory Calibration"} in vm["categories"] and cat_of(vm, "G29") == "WM Factory Calibration")
check("update: untouched calibration macros from Offset Calibration and Raspberry Pi move to RPI Calibration, real names",
      all(cat_of(vm, n) == "RPI Calibration" for n in ["WM_OFFSETS_RAPID", "WM_Z_TRIM", "WM_BED_LEVELING", "WM_AUTO_SPEED"])
      and next(m for m in vm["stored"] if m["name"] == "WM_AUTO_SPEED")["alias"] == "")
check("update: WM_UNLOAD_MENU moves to WM Ultra Filament", cat_of(vm, "WM_UNLOAD_MENU") == "WM Ultra Filament" and next(m for m in vm["stored"] if m["name"] == "WM_UNLOAD_MENU")["alias"] == "")
check("update: WM_BED_SOAK is hidden", next(m for m in vm["stored"] if m["name"] == "WM_BED_SOAK")["visible"] is False and cat_of(vm, "WM_BED_SOAK") == "-")
check("update: one the user recoloured stays in Raspberry Pi; the chamber light moves to ZR Tools", cat_of(vm, "WM_SCREWS_CAL") == "Raspberry Pi" and cat_of(vm, "WM_CHAMBER_LIGHT") == "ZR Tools" and next(m for m in vm["stored"] if m["name"] == "WM_CHAMBER_LIGHT")["color"] == "#9c27b0")
check("update: the empty Offset Calibration is removed; Raspberry Pi stays while your macro is in it; ids kept",
      [c["name"] for c in vm["categories"]] == ["Raspberry Pi", "RPI Calibration", "AcePro", "WM Factory Calibration", "WM Ultra Filament", "ZR Tools"] and vm["categories"][0]["id"] == "10")
check("update: a new macro is sorted with its name", cat_of(vm, "WM_LIVE_Z_MENU") == "RPI Calibration" and rm["moved"] == 7 and rm["categorized"] == 1)
check("update: a second run changes nothing", not wmfc.plan(om, vm, hm, now_ms=6000)[2]["changed"])
kept = json.loads(json.dumps(old)); kept["stored"][1]["categoryId"] = "20"; kept["stored"][1]["color"] = "#123456"
vk = wmfc.plan(om, kept, oldh, now_ms=5000)[0]
check("update: Offset Calibration stays while a macro you recoloured is still in it", "Offset Calibration" in [c["name"] for c in vk["categories"]] and cat_of(vk, "WM_Z_TRIM") == "Offset Calibration")
mine2 = json.loads(json.dumps(old)); mine2["categories"].append({"id": "40", "name": "WM Factory Calibration"})
vr = wmfc.plan(om, mine2, oldh, now_ms=5000)[0]
check("update: no rename when WM Factory Calibration already exists", "WM Ultra Calibration" in [c["name"] for c in vr["categories"]])
for m in vm["stored"]:
    if m["name"] == "WM_AUTO_SPEED":
        m["categoryId"] = "10"; m["color"] = "#2196f3"; m["alias"] = ""      # the user puts it back in Raspberry Pi
vn, hn, rn = wmfc.plan(om, vm, hm, now_ms=6000)
check("update: a macro the user moves back afterwards is not moved again", cat_of(vn, "WM_AUTO_SPEED") == "Raspberry Pi" and not rn["changed"])
check("the input is not modified by a move", old["stored"][0]["categoryId"] == "20" and len(old["categories"]) == 4)


allpi = json.loads(json.dumps(old)); allpi["stored"] = [m for m in allpi["stored"] if m["name"] != "WM_SCREWS_CAL"]
vp = wmfc.plan([n for n in om if n != "WM_SCREWS_CAL"], allpi, [h for h in oldh if h != "WM_SCREWS_CAL"], now_ms=5000)[0]
check("update: Raspberry Pi is removed once nothing is left in it", "Raspberry Pi" not in [c["name"] for c in vp["categories"]] and cat_of(vp, "WM_CHAMBER_LIGHT") == "ZR Tools")
check("a WM_ macro that is in no list stays uncategorized (Claude asks where it goes)", wmfc.match("WM_SOMETHING_NEW") is None)

print("one colour per category")
check("every category has its own colour", len({c[1].lower() for c in wmfc.CATEGORIES}) == len(wmfc.CATEGORIES))
mix = {"stored": [entry("WM_OFFSETS_RAPID", categoryId="5", color="#2196f3"), entry("WM_Z_TRIM", categoryId="5", color=""),
                  entry("WM_BED_PID", categoryId="5", color="#abcdef"), entry("G29", categoryId="6", color="#e91e63")],
       "categories": [{"id": "5", "name": "RPI Calibration"}, {"id": "6", "name": "WM Factory Calibration"}], "expanded": [0, 0, 1]}
vc, hc, rc_ = wmfc.plan(["WM_OFFSETS_RAPID", "WM_Z_TRIM", "WM_BED_PID", "G29"], mix, ["WM_OFFSETS_RAPID", "WM_Z_TRIM", "WM_BED_PID", "G29"], now_ms=7000)
col = {m["name"]: m["color"] for m in vc["stored"]}
check("installer colours (or none) become the category's colour", col["WM_OFFSETS_RAPID"] == "#e91e63" and col["WM_Z_TRIM"] == "#e91e63" and col["G29"] == "#ffeb3b" and rc_.get("recoloured") == 3)
check("a colour you picked yourself stays", col["WM_BED_PID"] == "#abcdef")
check("after recolouring a second run changes nothing", not wmfc.plan(["WM_OFFSETS_RAPID", "WM_Z_TRIM", "WM_BED_PID", "G29"], vc, hc, now_ms=8000)[2]["changed"])


print("1.16.2: no aliases")
OLDV = {"stored": [entry("WM_BED_LEVELING", alias="Bed Leveling", categoryId="1", color="#e91e63"), entry("WM_FIRST_RUN_CAL", alias="First Run Calibration", categoryId="1", color="#e91e63"),
                   entry("WM_OFFSETS_RAPID", alias="My own name", categoryId="1", color="#e91e63"), entry("G29")],
        "categories": [{"id": "1", "name": "RPI Calibration"}], "expanded": [0]}
vA, hA, rA = wmfc.plan(["WM_BED_LEVELING", "WM_FIRST_RUN_CAL", "WM_OFFSETS_RAPID", "G29"], OLDV, ["WM_BED_LEVELING", "WM_FIRST_RUN_CAL", "WM_OFFSETS_RAPID", "G29"], now_ms=1000)
al = {m["name"]: m["alias"] for m in vA["stored"]}
check("a new sort writes no alias at all", all(m["alias"] == "" for m in v["stored"]) and wmfc.ALIASES == {})
check("the readable names of 1.10.0 to 1.16.1 are cleared once, Fluidd then shows the real name", al["WM_BED_LEVELING"] == "" and al["WM_FIRST_RUN_CAL"] == "" and rA.get("unaliased") == 2)
check("an alias you typed yourself stays", al["WM_OFFSETS_RAPID"] == "My own name")
vB, hB, rB = wmfc.plan(["WM_BED_LEVELING", "WM_FIRST_RUN_CAL", "WM_OFFSETS_RAPID", "G29"], vA, hA, now_ms=2000)
check("a second run changes nothing", not rB["changed"] and next(m for m in vB["stored"] if m["name"] == "WM_OFFSETS_RAPID")["alias"] == "My own name")
vC = json.loads(json.dumps(vA)); next(m for m in vC["stored"] if m["name"] == "WM_BED_LEVELING")["alias"] = "Bed Leveling"
vD, hD, rD = wmfc.plan(["WM_BED_LEVELING", "WM_FIRST_RUN_CAL", "WM_OFFSETS_RAPID", "G29"], vC, hA, now_ms=3000)
check("an alias you set back later is left alone (the cleanup runs once)", next(m for m in vD["stored"] if m["name"] == "WM_BED_LEVELING")["alias"] == "Bed Leveling")

print("against a fake Moonraker")
DB = {("fluidd", "macros"): {"stored": [entry("G29")], "categories": [], "expanded": [0]}}
STATE = {"klippy": "ready", "writes": 0}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path); q = parse_qs(u.query)
        if u.path == "/printer/info":
            return self._send(200, {"result": {"state": STATE["klippy"]}})
        if u.path == "/printer/objects/list":
            return self._send(200, {"result": {"objects": ["configfile", "heaters"] + ["gcode_macro " + m for m in MACROS]}})
        if u.path == "/server/database/item":
            k = (q["namespace"][0], q["key"][0])
            return self._send(200, {"result": {"namespace": k[0], "key": k[1], "value": DB[k]}}) if k in DB else self._send(404, {"error": {"message": "not found"}})
        self._send(404, {})

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0)); d = json.loads(self.rfile.read(n))
        DB[(d["namespace"], d["key"])] = d["value"]; STATE["writes"] += 1
        self._send(200, {"result": {}})


srv = HTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
URL = "http://127.0.0.1:%d" % srv.server_address[1]
tmp = tempfile.mkdtemp()
bk = os.path.join(tmp, "before.json")


def run(*extra):
    p = subprocess.run([sys.executable, "-I", SCRIPT, "apply", "--url", URL, *extra], capture_output=True, text=True)
    return p.returncode, p.stdout.strip()


rc, out = run("--dry-run")
check("dry run says what it would do and writes nothing", rc == 0 and "dry run" in out and STATE["writes"] == 0)
rc, out = run("--backup", bk)
check("apply writes the Fluidd macros and our own record, and saves the old settings", rc == 0 and STATE["writes"] == 2 and ("wm_ultra", "fluidd_categories") in DB and json.load(open(bk))["fluidd_macros"]["stored"][0]["name"] == "G29")
check("the user's category-less G29 that existed before was sorted too", cat_of(DB[("fluidd", "macros")], "G29") == "WM Factory Calibration")
before = STATE["writes"]
rc, out = run("--backup", bk)
check("a second apply says nothing is new and writes nothing", rc == 0 and "nothing new" in out and STATE["writes"] == before)
STATE["klippy"] = "startup"
rc, out = run("--wait", "0")
check("Klipper not ready: exit code 2 with a plain message", rc == 2 and "Klipper is startup" in out)
srv.shutdown()
rc, out = subprocess.run([sys.executable, "-I", SCRIPT, "apply", "--url", "http://127.0.0.1:1"], capture_output=True, text=True).returncode, ""
check("Moonraker not running: exit code 2", rc == 2)

print("passed: %d   failed: %d" % (0, len(FAILED)) if False else ("failed: %d" % len(FAILED)))
sys.exit(1 if FAILED else 0)
