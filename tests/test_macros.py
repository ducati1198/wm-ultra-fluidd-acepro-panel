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
o = run(stats, "_WM_STATS_RESET")
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
A0 = {"mode": "idle", "manual": -2, "pstate": "printing", "assist": -1, "ace_instance": 0, "resync": 0}
o = run(ace, "_WM_ACE_ASSIST_SYNC", variables={"current_extruder": 0}, state="printing", gvars={"_WM_ACE": dict(A0)})
check("printing with T0 on the carriage: assist on for T0", "ACE_ENABLE_FEED_ASSIST T=0" in o)
o = run(ace, "_WM_ACE_ASSIST_SYNC", variables={"current_extruder": 99}, state="printing", gvars={"_WM_ACE": dict(A0, assist=0)})
check("printing but the tool is parked (99): assist off, nothing switched on", "ACE_DISABLE_FEED_ASSIST T=0" in o and not any("ENABLE_FEED" in l and "DISABLE" not in l for l in o))
o = run(ace, "_WM_ACE_ASSIST_SYNC", variables={"current_extruder": 0}, state="standby", gvars={"_WM_ACE": dict(A0, assist=1)})
check("print ended: assist off, the hand choice is cleared", "ACE_DISABLE_FEED_ASSIST T=1" in o and "SET_GCODE_VARIABLE MACRO=_WM_ACE VARIABLE=manual VALUE=-2" in o and not any(l.startswith("ACE_ENABLE") for l in o))
o = run(ace, "_WM_ACE_ASSIST_SYNC", variables={"current_extruder": 2}, state="standby", gvars={"_WM_ACE": dict(A0, pstate="standby", manual=3, assist=-1)})
check("assist set by hand (_ACE_WM_ASSIST T=3) wins while no print starts or ends", "ACE_ENABLE_FEED_ASSIST T=3" in o)
o = run(ace, "_WM_ACE_ASSIST_SYNC", variables={"current_extruder": 0}, state="printing", gvars={"_WM_ACE": dict(A0, mode="load_fast")})
check("no assist change while a load runs", not any("FEED_ASSIST" in l for l in o))
AI = lambda slot, conn="connected": {"connection_state": conn, "feed_assist_slot": slot}
def arun(w, cur, state="printing", ace=None):
    env = jinja2.Environment("{%", "%}", "{", "}", extensions=["jinja2.ext.do"])
    printer = {"save_variables": {"variables": {"current_extruder": cur}}, "print_stats": {"state": state}, "gcode_macro _WM_ACE": w}
    if ace is not None: printer["ace_instance_0"] = ace
    out = env.from_string(globals()["ace"]["_WM_ACE_ASSIST_SYNC"]).render(params={}, printer=printer)
    return [l.strip() for l in out.splitlines() if l.strip() and not l.strip().startswith("#")]
AW = dict(A0, ace_instance=0, resync=0, assist=0)
o = arun(dict(AW), 0, ace=AI(-1))
check("ACE came back without feed assist: on again for the toolhead that prints, then a 10 s hold", "ACE_ENABLE_FEED_ASSIST T=0" in o and "SET_GCODE_VARIABLE MACRO=_WM_ACE VARIABLE=resync VALUE=10" in o and not any(l.startswith("ACE_DISABLE") for l in o))
check("inside the hold: not sent again", not any(l.startswith("ACE_ENABLE") for l in arun(dict(AW, resync=4), 0, ace=AI(-1))))
check("ACE reports our slot: nothing to do", arun(dict(AW), 0, ace=AI(0)) == [])
check("ACE not connected yet: nothing sent", not any(l.startswith("ACE_ENABLE") for l in arun(dict(AW), 0, ace=AI(-1, "disconnected"))))
o = arun(dict(AW), 1, ace=AI(-1))
check("the endless spool swapped to T1 meanwhile: assist goes on for T1, the lost T0 is not switched off or on", "ACE_ENABLE_FEED_ASSIST T=1" in o and not any("T=0" in l for l in o))
w = ace["_wm_ace_watch"]
check("the watcher only calls _WM_ACE_ASSIST_SYNC for feed assist (no assist command of its own)", "_WM_ACE_ASSIST_SYNC" in w and "ACE_ENABLE_FEED_ASSIST" not in w and "toolhead.extruder" not in w)

print("Endless spool (automatic swap, sets of 2 to 4)")
import jinja2 as _j


def erun(name, params=None, variables=None, state="paused", sensors=None, w=None, extra=None):
    """like run(), with the filament sensors and the objects the endless macros read"""
    env = _j.Environment("{%", "%}", "{", "}", extensions=["jinja2.ext.do"])
    env.globals["action_raise_error"] = lambda m: (_ for _ in ()).throw(Err(m))
    W = {"from": -1, "to": -1, "swap_file": "", "tried": 0, "ofx": 0.0, "ofy": 0.0, "ofz": 0.1, "ocx": 0.3, "ocy": 0.35, "ocz": 0.004, "pending": 0, "keeps": 1, "fake": -1,
         "tangle": -1, "out0": 0, "out1": 0, "out2": 0, "out3": 0}
    W.update(w or {})
    printer = {"save_variables": {"variables": dict(variables or {})}, "print_stats": {"state": state, "print_duration": 100.0, "filename": "a.gcode"},
               "gcode_macro _WM_ENDLESS": W, "gcode_macro _WM_PAUSE_STATE": {"active": 1}, "gcode_macro _WM_LIVEZ": {},
               "gcode_macro RESUME": {"resume_temperature%d" % i: 220.0 for i in range(4)},
               "gcode_move": {"homing_origin": type("O", (), {"x": 0.0, "y": 0.0, "z": 0.096})()}}
    for i, det in enumerate(sensors or [True] * 4):
        printer["filament_switch_sensor filament%d" % i] = {"filament_detected": det}
    printer.update(extra or {})
    out = env.from_string(endl[name]).render(params=params or {}, printer=printer)
    return [l.strip() for l in out.splitlines() if l.strip() and not l.strip().startswith("#")]


SAME = {"wm_endless": 1, "current_extruder": 0}
for i in range(4): SAME.update({"zr_t%d_mat" % i: 1, "zr_t%d_color" % i: 255})
V3 = dict(SAME, zr_t3_mat=2)
E0 = [False, True, True, True]
o = erun("_WM_ENDLESS_TICK", variables=SAME, sensors=E0)
check("T0 empty, all identical: T1 takes over", "_WM_ENDLESS_CONTINUE FROM=0 TO=1" in o and "SET_GCODE_VARIABLE MACRO=_WM_ENDLESS VARIABLE=tried VALUE=1" in o)
o = erun("_WM_ENDLESS_TICK", variables=dict(SAME, current_extruder=3), sensors=[True, True, True, False])
check("T3 empty: starts again from T0", "_WM_ENDLESS_CONTINUE FROM=3 TO=0" in o)
o = erun("_WM_ENDLESS_TICK", variables=SAME, sensors=[False, False, True, True])
check("the next one is empty too: it is skipped (T2)", "_WM_ENDLESS_CONTINUE FROM=0 TO=2" in o)
o = erun("_WM_ENDLESS_TICK", variables=dict(V3, current_extruder=2), sensors=[True, True, False, True])
check("set of 3: T2 empty goes to T0, never to T3 (other material)", "_WM_ENDLESS_CONTINUE FROM=2 TO=0" in o)
o = erun("_WM_ENDLESS_TICK", variables=dict(SAME, zr_t1_color=1, zr_t2_color=2, zr_t3_color=3), sensors=E0)
check("no identical toolhead: no swap, one message, the pause is marked as handled", not any(l.startswith("_WM_ENDLESS_CONTINUE") for l in o) and any("stays paused" in l for l in o) and any("VARIABLE=tried VALUE=1" in l for l in o))
o = erun("_WM_ENDLESS_TICK", variables=dict(SAME, zr_t0_mat=None, zr_t1_mat=None, zr_t2_mat=None, zr_t3_mat=None), sensors=E0)
check("material not set: never identical", not any(l.startswith("_WM_ENDLESS_CONTINUE") for l in o))
check("toolhead on the carriage has filament: nothing happens", erun("_WM_ENDLESS_TICK", variables=SAME) == [])
HUB_OFF = {"filament_switch_sensor path_0": {"filament_detected": False}, "filament_switch_sensor path_1": {"filament_detected": False}}
check("a hub (tangle) sensor that reads off does not make a toolhead empty", erun("_WM_ENDLESS_TICK", variables=SAME, extra=HUB_OFF) == [])
check("a spare is not skipped for its hub (tangle) sensor", "_WM_ENDLESS_CONTINUE FROM=0 TO=1" in erun("_WM_ENDLESS_TICK", variables=SAME, sensors=E0, extra=HUB_OFF))
o = erun("_WM_ENDLESS_TANGLE", {"T": "2"}, state="paused")
check("_WM_ENDLESS_TANGLE remembers the toolhead (only in a print)", "SET_GCODE_VARIABLE MACRO=_WM_ENDLESS VARIABLE=tangle VALUE=2" in o and erun("_WM_ENDLESS_TANGLE", {"T": "2"}, state="standby") == [])
o = erun("_WM_ENDLESS_TICK", variables=SAME, w={"tangle": 0})
check("tangle on the printing toolhead: swap, toolhead out of the line, window with Fixed and Close", "_WM_ENDLESS_CONTINUE FROM=0 TO=1" in o and "SET_GCODE_VARIABLE MACRO=_WM_ENDLESS VARIABLE=out0 VALUE=1" in o and any("prompt_footer_button Fixed|_WM_ENDLESS_FIXED T=0" in l for l in o) and any("prompt_show" in l for l in o) and o.index("_WM_ENDLESS_CONTINUE FROM=0 TO=1") > max(i for i, l in enumerate(o) if "prompt_show" in l))
check("Swap on a tangle off: a tangle starts nothing", erun("_WM_ENDLESS_TICK", variables=dict(SAME, wm_endless_tangle=0), w={"tangle": 0}) == [])
check("a tangle of another toolhead than the one on the carriage starts nothing", erun("_WM_ENDLESS_TICK", variables=SAME, w={"tangle": 2}) == [])
o = erun("_WM_ENDLESS_TICK", variables=dict(SAME, zr_t1_color=1, zr_t2_color=2, zr_t3_color=3), w={"tangle": 0})
check("tangle with no identical toolhead: stays paused, nothing is taken out of the line", not any(l.startswith("_WM_ENDLESS_CONTINUE") or "VARIABLE=out0" in l for l in o) and any("stays paused" in l for l in o))
check("a toolhead that is out of the line is skipped as a spare", "_WM_ENDLESS_CONTINUE FROM=0 TO=2" in erun("_WM_ENDLESS_TICK", variables=SAME, sensors=E0, w={"out1": 1}))
o = erun("_WM_ENDLESS_TICK", variables=SAME, state="printing", sensors=[True, False, True, True], w={"out1": 1})
check("out of the line + its toolhead sensor goes off: reload seen (2)", "SET_GCODE_VARIABLE MACRO=_WM_ENDLESS VARIABLE=out1 VALUE=2" in o)
o = erun("_WM_ENDLESS_TICK", variables=SAME, state="printing", w={"out1": 2})
check("reloaded: back in the line", "SET_GCODE_VARIABLE MACRO=_WM_ENDLESS VARIABLE=out1 VALUE=0" in o)
check("print over: every toolhead is back in the line", "SET_GCODE_VARIABLE MACRO=_WM_ENDLESS VARIABLE=out3 VALUE=0" in erun("_WM_ENDLESS_TICK", variables=SAME, state="complete", w={"out3": 1}))
check("resumed: the remembered tangle is cleared", "SET_GCODE_VARIABLE MACRO=_WM_ENDLESS VARIABLE=tangle VALUE=-1" in erun("_WM_ENDLESS_TICK", variables=SAME, state="printing", w={"tangle": 0}))
o = erun("_WM_ENDLESS_FIXED", {"T": "1"}, variables=SAME, w={"out1": 1})
check("_WM_ENDLESS_FIXED T=1 puts the toolhead back and closes the window", "SET_GCODE_VARIABLE MACRO=_WM_ENDLESS VARIABLE=out1 VALUE=0" in o and any("prompt_end" in l for l in o))
check("_WM_ENDLESS_FIXED refuses a wrong toolhead", raises(lambda: erun("_WM_ENDLESS_FIXED", {"T": "7"}, variables=SAME)))
ACE = {"gcode_macro _WM_ACE": {"ace_instance": 0}, "ace_instance_0": {"connection_state": "connected", "slots": [{"status": "ready"}, {"status": "empty"}, {"status": "ready"}, {"status": "ready"}]}}
check("with an ACE: a spare whose ACE slot is empty is skipped", "_WM_ENDLESS_CONTINUE FROM=0 TO=2" in erun("_WM_ENDLESS_TICK", variables=SAME, sensors=E0, extra=ACE))
check("ACE not connected: its slots do not count", "_WM_ENDLESS_CONTINUE FROM=0 TO=1" in erun("_WM_ENDLESS_TICK", variables=SAME, sensors=E0, extra=dict(ACE, ace_instance_0=dict(ACE["ace_instance_0"], connection_state="disconnected"))))
check("ACE Pro switched off: its slots do not count", "_WM_ENDLESS_CONTINUE FROM=0 TO=1" in erun("_WM_ENDLESS_TICK", variables=dict(SAME, ace_global_enabled=False), sensors=E0, extra=ACE))
o = erun("_WM_ENDLESS_SET", {"TANGLE": "0"}, variables=SAME)
check("_WM_ENDLESS_SET TANGLE=0 is saved (stays over a Klipper restart)", "SAVE_VARIABLE VARIABLE=wm_endless_tangle VALUE=0" in o)
check("switch off: nothing", erun("_WM_ENDLESS_TICK", variables=dict(SAME, wm_endless=0), sensors=E0) == [])
check("swap automatically off: nothing", erun("_WM_ENDLESS_TICK", variables=dict(SAME, wm_endless_auto=0), sensors=E0) == [])
check("already handled in this pause: nothing", erun("_WM_ENDLESS_TICK", variables=SAME, sensors=E0, w={"tried": 1}) == [])
check("not paused: the handled mark is cleared", "SET_GCODE_VARIABLE MACRO=_WM_ENDLESS VARIABLE=tried VALUE=0" in erun("_WM_ENDLESS_TICK", variables=SAME, state="printing", w={"tried": 1}))
check("the test variable fake makes a toolhead empty", "_WM_ENDLESS_CONTINUE FROM=0 TO=1" in erun("_WM_ENDLESS_TICK", variables=SAME, w={"fake": 0}))
o = erun("_WM_ENDLESS_CONTINUE", {"FROM": "0", "TO": "1"}, variables=SAME, sensors=E0)
check("the swap: offsets of the empty head stored, tool change from the park position, no move back to the part", "_CHANGE_TOOL T=1" in o and "SET_GCODE_VARIABLE MACRO=_WM_ENDLESS VARIABLE=ofz VALUE=0.096" in o and not any(l.startswith("RESTORE_GCODE_STATE") or l.startswith("G1") for l in o) and o[-1] == "_WM_ENDLESS_3")
check("refused when the print is not paused", raises(lambda: erun("_WM_ENDLESS_CONTINUE", {"FROM": "0", "TO": "1"}, variables=SAME, state="printing")))
check("refused when the spare has no filament", raises(lambda: erun("_WM_ENDLESS_CONTINUE", {"FROM": "0", "TO": "1"}, variables=SAME, sensors=[False, False, True, True])))
check("refused when FROM is not on the carriage", raises(lambda: erun("_WM_ENDLESS_CONTINUE", {"FROM": "2", "TO": "1"}, variables=SAME)))
o = erun("_WM_ENDLESS_3", variables=dict(SAME, current_extruder=1), w={"from": 0, "to": 1})
check("after the tool change: temperature and tool mapping go to the spare, RESUME does the only purge, then the last step", "SET_GCODE_VARIABLE MACRO=RESUME VARIABLE=resume_temperature1 VALUE=220.0" in o and "SET_GCODE_VARIABLE MACRO=RESUME VARIABLE=resume_temperature0 VALUE=0" in o and "SAVE_VARIABLE VARIABLE=box_modify_t0_backup VALUE=1" in o and o[-2:] == ["RESUME", "_WM_ENDLESS_4"] and not any(l.startswith("E_axis_move") or l.startswith("WIPE_NOZZLE") or l.startswith("M109") for l in o) and "SET_GCODE_VARIABLE MACRO=_WM_ENDLESS VARIABLE=pending VALUE=1" in o)
check("tool change failed: error, no resume", raises(lambda: erun("_WM_ENDLESS_3", variables=SAME, w={"from": 0, "to": 1})))
o = erun("_WM_ENDLESS_4", variables=SAME, w={"pending": 1, "to": 1, "ofz": 0.09608, "ocz": 0.0036, "ofx": 0.0, "ocx": 0.309375, "ofy": 0.0, "ocy": 0.354688})
check("last step: the spare head moves by the difference of the offsets (no print state test), inside a saved state", "G1 X0.3094 Y0.3547 Z-0.0925 F600" in o and o.index("SAVE_GCODE_STATE NAME=_wm_endless") < o.index("G91") < o.index("RESTORE_GCODE_STATE NAME=_wm_endless") and "SET_GCODE_VARIABLE MACRO=_WM_ENDLESS VARIABLE=pending VALUE=0" in o)
check("last step runs once only", erun("_WM_ENDLESS_4", variables=SAME, w={"pending": 0}) == [])
check("keeps=0 (a Klipper whose restore brings the offsets back): no move", not any(l.startswith("G1") for l in erun("_WM_ENDLESS_4", variables=SAME, w={"pending": 1, "keeps": 0})))
o = erun("_WM_ENDLESS_SET", {"AUTO": "0"}, variables=SAME)
check("_WM_ENDLESS_SET AUTO=0 saves wm_endless_auto and leaves the main switch", "SAVE_VARIABLE VARIABLE=wm_endless_auto VALUE=0" in o and not any("VARIABLE=wm_endless VALUE" in l for l in o))
check("the chain macro is gone", "WM_ENDLESS_CHAIN_SET" not in endl)
check("the watcher only calls _WM_ENDLESS_TICK (renders when it runs)", "_WM_ENDLESS_TICK" in endl["_WM_ENDLESS_WATCH"] and "printer." not in endl["_WM_ENDLESS_WATCH"])

# ---- rpi_ace.cfg: short hold after an unload, and the Load window (1.8.0)
ace = load("rpi_ace.cfg")
W = {"tool": 0, "mode": "unload_hub", "unload_hold": 5}
o = run(ace, "_WM_ACE_FINISH", gvars={"_WM_ACE": W})
check("after an unload the hold is unload_hold and the window is armed", "SET_GCODE_VARIABLE MACRO=_WM_ACE VARIABLE=hold VALUE=5" in o and "SET_GCODE_VARIABLE MACRO=_WM_ACE VARIABLE=hold_ask VALUE=1" in o)
o = run(ace, "_WM_ACE_FINISH", gvars={"_WM_ACE": dict(W, mode="load_final")})
check("after a load the hold stays 90 s and no window is armed", "SET_GCODE_VARIABLE MACRO=_WM_ACE VARIABLE=hold VALUE=90" in o and "SET_GCODE_VARIABLE MACRO=_WM_ACE VARIABLE=hold_ask VALUE=0" in o)
o = run(ace, "_WM_ACE_ASK_LOAD", {"T": "2"})
check("Load window: closes any open window first", o[0] == 'RESPOND TYPE=command MSG="action:prompt_end"')
check("Load window: asks for T3, Load and No buttons", any("prompt_begin Load T3" in l for l in o) and any("Load T3|_WM_ACE_ASK_YES T=2|primary" in l for l in o) and any("No|_WM_ACE_ASK_NO T=2" in l for l in o))
check("Load window: bad T only reports", not any("prompt_begin" in l for l in run(ace, "_WM_ACE_ASK_LOAD", {"T": "9"})))
check("Load button loads the tool", "ACE_WM_LOAD T=1" in run(ace, "_WM_ACE_ASK_YES", {"T": "1"}))
check("No button loads nothing", not any(l.startswith("ACE_WM_LOAD") for l in run(ace, "_WM_ACE_ASK_NO", {"T": "1"})))
check("rpi_ace.cfg needs no macro of the Pi installer (_WM_FAIL)", "_WM_FAIL" not in open(os.path.join(CFG, "rpi_ace.cfg")).read())
check("no ; # * inside a RESPOND MSG of the new macros", not any(c in l.split('MSG="', 1)[1] for k in ("_WM_ACE_ASK_LOAD", "_WM_ACE_ASK_YES", "_WM_ACE_ASK_NO") for l in ace[k].splitlines() if 'MSG="' in l for c in ";#*"))

print(f"\npassed: {PASS}  failed: {FAIL}")
sys.exit(1 if FAIL else 0)
