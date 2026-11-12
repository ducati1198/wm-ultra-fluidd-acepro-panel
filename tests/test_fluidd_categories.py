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


MACROS = ["ACE_WM_LOAD", "WM_ENDLESS_SET", "WM_STATS_RESET", "WM_SET_TOOL_MAP", "WM_BED_LEVELING", "WM_SCREWS_CAL", "WM_OFFSETS_RAPID", "G29",
          "RAPID_MODE", "T0", "PARK_CURRENT_TOOL", "LOAD_FILAMENT", "WIPE_NOZZ", "ZR_LOAD", "START_PRINT", "TEST_XY",
          "TEST_STREAM_DELAY", "HYPERLAPSE", "M104", "z_rise", "_HIDDEN_HELPER", "SOMETHING_ELSE"]

print("rules")
v, h, r = wmfc.plan(MACROS, None, [], now_ms=1000)
check("AcePro: ACE_*, WM_ENDLESS_*, WM_STATS_*, WM_SET_TOOL_MAP", all(cat_of(v, n) == "AcePro" for n in ["ACE_WM_LOAD", "WM_ENDLESS_SET", "WM_STATS_RESET", "WM_SET_TOOL_MAP"]))
check("Raspberry Pi: the other WM_* macros", cat_of(v, "WM_BED_LEVELING") == "Raspberry Pi" and cat_of(v, "WM_SCREWS_CAL") == "Raspberry Pi" and cat_of(v, "WM_OFFSETS_RAPID") == "Raspberry Pi")
check("WonderMaker factory macros land in their categories",
      cat_of(v, "G29") == "WM Ultra Calibration" and cat_of(v, "RAPID_MODE") == "WM Ultra Calibration" and cat_of(v, "T0") == "WM Ultra Tool Change"
      and cat_of(v, "PARK_CURRENT_TOOL") == "WM Ultra Tool Change" and cat_of(v, "LOAD_FILAMENT") == "WM Ultra Filament" and cat_of(v, "WIPE_NOZZ") == "WM Ultra Filament"
      and cat_of(v, "ZR_LOAD") == "ZR Tools" and cat_of(v, "START_PRINT") == "WM Ultra Print" and cat_of(v, "TEST_XY") == "WM Ultra Tests")
check("TEST_STREAM_DELAY goes to Timelapse, not Tests", cat_of(v, "TEST_STREAM_DELAY") == "Timelapse" and cat_of(v, "HYPERLAPSE") == "Timelapse")
check("colours", [m["color"] for m in v["stored"] if m["name"] == "ACE_WM_LOAD"] == ["#f44336"] and [m["color"] for m in v["stored"] if m["name"] == "WM_BED_LEVELING"] == ["#2196f3"]
      and [m["color"] for m in v["stored"] if m["name"] == "G29"] == ["#ffeb3b"])
check("helper macros are hidden, not categorized", all(next(m for m in v["stored"] if m["name"] == n)["visible"] is False and cat_of(v, n) == "-" for n in ["M104", "z_rise"]))
check("macros starting with _ and unknown macros are left out", not any(m["name"] in ("_HIDDEN_HELPER", "SOMETHING_ELSE") for m in v["stored"]))
check("categories are created in Fluidd's order, only the ones needed", [c["name"] for c in v["categories"]] == ["Raspberry Pi", "AcePro", "WM Ultra Calibration", "WM Ultra Tool Change", "WM Ultra Filament", "ZR Tools", "WM Ultra Print", "WM Ultra Tests", "Timelapse"])
check("new categories are expanded", v["expanded"] == [0, 0, 1, 2, 3, 4, 5, 6, 7, 8])
check("only the macros that exist are used (a printer without an ACE gets no AcePro category)", "AcePro" not in [c["name"] for c in wmfc.plan(["WM_BED_LEVELING", "G29"], None, [], now_ms=5)[0]["categories"]])
check("the report counts", r["categorized"] == 18 and r["hidden"] == 2 and r["kept"] == 0 and len(r["created"]) == 9)

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
check("the user's category-less G29 that existed before was sorted too", cat_of(DB[("fluidd", "macros")], "G29") == "WM Ultra Calibration")
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
