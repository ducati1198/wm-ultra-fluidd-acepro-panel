"""Renders the Jinja of the new macros (rpi_stats.cfg, rpi_endless.cfg) against a fake printer.
Run:  python3 -I tests/test_macros.py      (needs jinja2)"""
import os, re, sys
import jinja2

CFG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "config")


def load(fname):
    macros, cur, body = {}, None, None
    for line in open(os.path.join(CFG, fname), encoding="utf-8"):
        m = re.match(r"^\[(gcode_macro|delayed_gcode)\s+(\S+)\]", line)
        if m:
            cur, body = m.group(2), None
            macros[cur] = []
            continue
        if line.startswith("["):
            cur = None
        if cur is None:
            continue
        if re.match(r"^gcode:\s*$", line):
            body = macros[cur]
        elif body is not None:
            body.append(line[4:] if line.startswith("    ") else line)
    return {k: "".join(v) for k, v in macros.items()}


class Err(Exception):
    pass


def run(macros, name, params=None, variables=None, state="standby", gvars=None):
    env = jinja2.Environment("{%", "%}", "{", "}", extensions=["jinja2.ext.do"])
    env.globals["action_raise_error"] = lambda m: (_ for _ in ()).throw(Err(m))
    printer = {"save_variables": {"variables": dict(variables or {})}, "print_stats": {"state": state}}
    for k, v in (gvars or {}).items():
        printer["gcode_macro " + k] = v
    out = env.from_string(macros[name]).render(params=params or {}, printer=printer)
    return [l.strip() for l in out.splitlines() if l.strip() and not l.strip().startswith("#")]


PASS = FAIL = 0


def check(desc, cond):
    global PASS, FAIL
    if cond: PASS += 1; print("  ok   ", desc)
    else: FAIL += 1; print("  FAIL ", desc)


def raises(fn):
    try:
        fn(); return False
    except Err:
        return True


stats = load("rpi_stats.cfg")
endl = load("rpi_endless.cfg")

print("Tool map")
o = run(stats, "WM_SET_TOOL_MAP", {"MAP": "0:2,1:3"})
check("sets both pairs", "SAVE_VARIABLE VARIABLE=box_modify_t0 VALUE=2" in o and "SAVE_VARIABLE VARIABLE=box_modify_t1_backup VALUE=3" in o)
check("rejects head 4", raises(lambda: run(stats, "WM_SET_TOOL_MAP", {"MAP": "0:4"})))
check("rejects garbage", raises(lambda: run(stats, "WM_SET_TOOL_MAP", {"MAP": "abc"})))
check("refuses while paused", raises(lambda: run(stats, "WM_SET_TOOL_MAP", {"MAP": "0:1"}, state="paused")))
o = run(stats, "WM_SET_TOOL_MAP", {"MAP": "0:2", "FILE": "a.gcode", "KEEP_EXISTING": "1"}, {"wm_map_file": "a.gcode"})
check("KEEP_EXISTING keeps the Fluidd choice", not any(l.startswith("SAVE_VARIABLE") for l in o))
o = run(stats, "WM_SET_TOOL_MAP", {"MAP": "0:2", "FILE": "b.gcode", "KEEP_EXISTING": "1"}, {"wm_map_file": "a.gcode"})
check("other file: map applied", any("box_modify_t0 VALUE=2" in l for l in o))

print("Counters")
g = {"_WM_STATS": {"last": -1}}
o = run(stats, "_WM_STATS_POLL", variables={"current_extruder": 1}, gvars=g)
check("first reading only remembers", not any(l.startswith("SAVE_VARIABLE") for l in o) and any("VARIABLE=last VALUE=1" in l for l in o))
g = {"_WM_STATS": {"last": 1}}
o = run(stats, "_WM_STATS_POLL", variables={"current_extruder": 2, "wm_stat_changes": 4, "wm_stat_head2": 1}, gvars=g)
check("a change counts", "SAVE_VARIABLE VARIABLE=wm_stat_changes VALUE=5" in o and "SAVE_VARIABLE VARIABLE=wm_stat_head2 VALUE=2" in o)
o = run(stats, "_WM_STATS_POLL", variables={"current_extruder": 1}, gvars=g)
check("no change, no count", not any(l.startswith("SAVE_VARIABLE") for l in o))
o = run(stats, "_WM_STATS_POLL", variables={"current_extruder": 99}, gvars=g)
check("invalid value ignored", not any(l.startswith("SAVE_VARIABLE") for l in o))
check("poll reschedules itself", any("UPDATE_DELAYED_GCODE ID=_WM_STATS_POLL" in l for l in run(stats, "_WM_STATS_POLL", variables={"current_extruder": 1}, gvars=g)))
o = run(stats, "WM_STATS_RESET")
check("reset zeroes 5 values", len([l for l in o if "VALUE=0" in l]) == 5)

print("Endless chain")
o = run(endl, "WM_ENDLESS_CHAIN_SET", {"HEAD": "0", "CHAIN": "2,1"})
check("saves the chain as text", any("wm_endless_chain0 VALUE=\"'2,1'\"" in l for l in o))
o = run(endl, "WM_ENDLESS_CHAIN_SET", {"HEAD": "0", "CHAIN": ""})
check("empty clears", any("wm_endless_chain0 VALUE=\"''\"" in l for l in o))
check("head in its own chain refused", raises(lambda: run(endl, "WM_ENDLESS_CHAIN_SET", {"HEAD": "0", "CHAIN": "0,1"})))
check("repeat refused", raises(lambda: run(endl, "WM_ENDLESS_CHAIN_SET", {"HEAD": "0", "CHAIN": "1,1"})))
check("bad head refused", raises(lambda: run(endl, "WM_ENDLESS_CHAIN_SET", {"HEAD": "7", "CHAIN": "1"})))

print(f"\npassed: {PASS}  failed: {FAIL}")
sys.exit(1 if FAIL else 0)
