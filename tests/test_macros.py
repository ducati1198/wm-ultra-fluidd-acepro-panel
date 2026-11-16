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


def run(macros, name, params=None, variables=None, state="standby", gvars=None, duration=0.0):
    env = jinja2.Environment("{%", "%}", "{", "}", extensions=["jinja2.ext.do"])
    env.globals["action_raise_error"] = lambda m: (_ for _ in ()).throw(Err(m))
    printer = {"save_variables": {"variables": dict(variables or {})}, "print_stats": {"state": state, "print_duration": duration}}
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
G0 = {"last_dur": -1.0, "pend": 0.0, "pend_tool": -1}
g = {"_WM_STATS": dict(G0, last=-1)}
o = run(stats, "_WM_STATS_TICK", variables={"current_extruder": 1}, gvars=g)
check("first reading only remembers", not any(l.startswith("SAVE_VARIABLE") for l in o) and any("VARIABLE=last VALUE=1" in l for l in o))
g = {"_WM_STATS": dict(G0, last=1)}
o = run(stats, "_WM_STATS_TICK", variables={"current_extruder": 2, "wm_stat_changes": 4, "wm_stat_head2": 1}, gvars=g)
check("a change counts", "SAVE_VARIABLE VARIABLE=wm_stat_changes VALUE=5" in o and "SAVE_VARIABLE VARIABLE=wm_stat_head2 VALUE=2" in o)
o = run(stats, "_WM_STATS_TICK", variables={"current_extruder": 1}, gvars=g)
check("no change, no count", not any(l.startswith("SAVE_VARIABLE") for l in o))
o = run(stats, "_WM_STATS_TICK", variables={"current_extruder": 99}, gvars=g)
check("invalid value ignored", not any(l.startswith("SAVE_VARIABLE") for l in o))
po = run(stats, "_WM_STATS_POLL", variables={"current_extruder": 1}, gvars=g)
check("poll only calls _WM_STATS_TICK, then reschedules itself (B-040: values read when the macro runs)",
      po == ["_WM_STATS_TICK", "UPDATE_DELAYED_GCODE ID=_WM_STATS_POLL DURATION=2"])
o = run(stats, "WM_STATS_RESET")
check("reset zeroes the counters and the print times", len([l for l in o if l.startswith("SAVE_VARIABLE") and l.endswith("VALUE=0")]) == 9 and any("wm_stat_time3 VALUE=0" in l for l in o))

print("Print time per toolhead")
def tick(cur, state, dur, last_dur, pend, pend_tool, extra=None):
    v = {"current_extruder": cur}; v.update(extra or {})
    return run(stats, "_WM_STATS_TICK", variables=v, state=state, duration=dur,
               gvars={"_WM_STATS": {"last": cur, "last_dur": last_dur, "pend": pend, "pend_tool": pend_tool}})
o = tick(0, "printing", 12.0, -1.0, 0.0, -1)
check("print start: nothing counted yet, the duration is remembered", not any(l.startswith("SAVE_VARIABLE") for l in o) and "SET_GCODE_VARIABLE MACRO=_WM_STATS VARIABLE=last_dur VALUE=12.0" in o and "SET_GCODE_VARIABLE MACRO=_WM_STATS VARIABLE=pend_tool VALUE=0" in o)
o = tick(0, "printing", 14.0, 12.0, 30.0, 0)
check("printing on T0: the 2 s are added to the unsaved time", "SET_GCODE_VARIABLE MACRO=_WM_STATS VARIABLE=pend VALUE=32.0" in o and not any(l.startswith("SAVE_VARIABLE") for l in o))
o = tick(0, "printing", 100.0, 98.0, 61.0, 0, {"wm_stat_time0": 500})
check("a minute collected: saved to wm_stat_time0", "SAVE_VARIABLE VARIABLE=wm_stat_time0 VALUE=561" in o and "SET_GCODE_VARIABLE MACRO=_WM_STATS VARIABLE=pend VALUE=2.0" in o)
o = tick(2, "printing", 50.0, 48.0, 20.0, 0, {"wm_stat_time0": 7})
check("tool change: the time of the old toolhead is saved, the new one starts", "SAVE_VARIABLE VARIABLE=wm_stat_time0 VALUE=27" in o and "SET_GCODE_VARIABLE MACRO=_WM_STATS VARIABLE=pend_tool VALUE=2" in o)
o = tick(1, "complete", 300.0, 298.0, 40.0, 1, {"wm_stat_time1": 100})
check("print end: the rest is saved, no more counting", "SAVE_VARIABLE VARIABLE=wm_stat_time1 VALUE=140" in o and "SET_GCODE_VARIABLE MACRO=_WM_STATS VARIABLE=last_dur VALUE=-1.0" in o and "SET_GCODE_VARIABLE MACRO=_WM_STATS VARIABLE=pend_tool VALUE=-1" in o)
o = tick(99, "printing", 30.0, 28.0, 0.0, -1)
check("no toolhead on the carriage: nothing counted", not any(l.startswith("SAVE_VARIABLE") for l in o) and "SET_GCODE_VARIABLE MACRO=_WM_STATS VARIABLE=pend VALUE=0.0" in o)
o = tick(0, "paused", 40.0, 40.0, 10.0, 0)
check("paused: print_duration stands still, nothing added", "SET_GCODE_VARIABLE MACRO=_WM_STATS VARIABLE=pend VALUE=10.0" in o)

print("Feed assist (B-040)")
ace = load("rpi_ace.cfg")
A0 = {"mode": "idle", "manual": -2, "pstate": "printing", "assist": -1}
o = run(ace, "_WM_ACE_ASSIST_SYNC", variables={"current_extruder": 0}, state="printing", gvars={"_WM_ACE": dict(A0)})
check("printing with T0 on the carriage: assist on for T0", "ACE_ENABLE_FEED_ASSIST T=0" in o)
o = run(ace, "_WM_ACE_ASSIST_SYNC", variables={"current_extruder": 99}, state="printing", gvars={"_WM_ACE": dict(A0, assist=0)})
check("printing but the tool is parked (99): assist off, nothing switched on", "ACE_DISABLE_FEED_ASSIST T=0" in o and not any("ENABLE_FEED" in l and "DISABLE" not in l for l in o))
o = run(ace, "_WM_ACE_ASSIST_SYNC", variables={"current_extruder": 0}, state="standby", gvars={"_WM_ACE": dict(A0, assist=1)})
check("print ended: assist off, the hand choice is cleared", "ACE_DISABLE_FEED_ASSIST T=1" in o and "SET_GCODE_VARIABLE MACRO=_WM_ACE VARIABLE=manual VALUE=-2" in o and not any(l.startswith("ACE_ENABLE") for l in o))
o = run(ace, "_WM_ACE_ASSIST_SYNC", variables={"current_extruder": 2}, state="standby", gvars={"_WM_ACE": dict(A0, pstate="standby", manual=3, assist=-1)})
check("assist set by hand (ACE_WM_ASSIST T=3) wins while no print starts or ends", "ACE_ENABLE_FEED_ASSIST T=3" in o)
o = run(ace, "_WM_ACE_ASSIST_SYNC", variables={"current_extruder": 0}, state="printing", gvars={"_WM_ACE": dict(A0, mode="load_fast")})
check("no assist change while a load runs", not any("FEED_ASSIST" in l for l in o))
w = ace["_wm_ace_watch"]
check("the watcher only calls _WM_ACE_ASSIST_SYNC for feed assist (no assist command of its own)", "_WM_ACE_ASSIST_SYNC" in w and "ACE_ENABLE_FEED_ASSIST" not in w and "toolhead.extruder" not in w)

print("Endless chain")
o = run(endl, "WM_ENDLESS_CHAIN_SET", {"HEAD": "0", "CHAIN": "2,1"})
check("saves the chain as text", any("wm_endless_chain0 VALUE=\"'2,1'\"" in l for l in o))
o = run(endl, "WM_ENDLESS_CHAIN_SET", {"HEAD": "0", "CHAIN": ""})
check("empty clears", any("wm_endless_chain0 VALUE=\"''\"" in l for l in o))
check("head in its own chain refused", raises(lambda: run(endl, "WM_ENDLESS_CHAIN_SET", {"HEAD": "0", "CHAIN": "0,1"})))
check("repeat refused", raises(lambda: run(endl, "WM_ENDLESS_CHAIN_SET", {"HEAD": "0", "CHAIN": "1,1"})))
check("bad head refused", raises(lambda: run(endl, "WM_ENDLESS_CHAIN_SET", {"HEAD": "7", "CHAIN": "1"})))

# ---- rpi_ace.cfg: short hold after an unload, and the Load window (1.8.0)
ace = load("rpi_ace.cfg")
W = {"tool": 0, "mode": "unload_hub", "unload_hold": 5}
o = run(ace, "_WM_ACE_FINISH", gvars={"_WM_ACE": W})
check("after an unload the hold is unload_hold and the window is armed", "SET_GCODE_VARIABLE MACRO=_WM_ACE VARIABLE=hold VALUE=5" in o and "SET_GCODE_VARIABLE MACRO=_WM_ACE VARIABLE=hold_ask VALUE=1" in o)
o = run(ace, "_WM_ACE_FINISH", gvars={"_WM_ACE": dict(W, mode="load_final")})
check("after a load the hold stays 90 s and no window is armed", "SET_GCODE_VARIABLE MACRO=_WM_ACE VARIABLE=hold VALUE=90" in o and "SET_GCODE_VARIABLE MACRO=_WM_ACE VARIABLE=hold_ask VALUE=0" in o)
o = run(ace, "_WM_ACE_ASK_LOAD", {"T": "2"})
check("Load window: closes any open window first", o[0] == 'RESPOND TYPE=command MSG="action:prompt_end"')
check("Load window: asks for T2, Load and No buttons", any("prompt_begin Load T2" in l for l in o) and any("Load T2|_WM_ACE_ASK_YES T=2|primary" in l for l in o) and any("No|_WM_ACE_ASK_NO T=2" in l for l in o))
check("Load window: bad T only reports", not any("prompt_begin" in l for l in run(ace, "_WM_ACE_ASK_LOAD", {"T": "9"})))
check("Load button loads the tool", "ACE_WM_LOAD T=1" in run(ace, "_WM_ACE_ASK_YES", {"T": "1"}))
check("No button loads nothing", not any(l.startswith("ACE_WM_LOAD") for l in run(ace, "_WM_ACE_ASK_NO", {"T": "1"})))
check("rpi_ace.cfg needs no macro of the Pi installer (_WM_FAIL)", "_WM_FAIL" not in open(os.path.join(CFG, "rpi_ace.cfg")).read())
check("no ; # * inside a RESPOND MSG of the new macros", not any(c in l.split('MSG="', 1)[1] for k in ("_WM_ACE_ASK_LOAD", "_WM_ACE_ASK_YES", "_WM_ACE_ASK_NO") for l in ace[k].splitlines() if 'MSG="' in l for c in ";#*"))

print(f"\npassed: {PASS}  failed: {FAIL}")
sys.exit(1 if FAIL else 0)
