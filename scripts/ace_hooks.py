#!/usr/bin/env python3
"""Three hook lines in WonderMaker's extruder0..3.cfg so the ACE load/unload macros can work with WM's insert routine.

  ace_hooks.py check CONFIG_DIR            prints one line per file: OK | MISSING | NOFILE | NOANCHOR ; exit 0 when all OK
  ace_hooks.py remove CONFIG_DIR           takes the three lines out again (uninstall); prints REMOVED | OK | NOFILE
  ace_hooks.py apply CONFIG_DIR            adds the missing lines (idempotent); prints ADDED | OK | NOANCHOR | NOFILE ; exit 1 on NOANCHOR

For tool n, inside [filament_switch_sensor filament<n>] -> insert_gcode:
  first line of the block      _WM_ACE_HEAD T=n
  just before filament_insert  _WM_ACE_GRAB T=n
  just after PARK_CURRENT_TOOL _WM_ACE_HEAD_DONE T=n
A file whose anchors are not found is left alone.
"""
import os, re, sys


def process(text, n):
    """returns (new_text, status) status: OK (nothing to do) | ADDED | NOANCHOR"""
    lines = text.split("\n")
    sec = next((i for i, l in enumerate(lines) if re.match(r"^\[filament_switch_sensor\s+filament%d\]\s*$" % n, l)), None)
    if sec is None: return text, "NOANCHOR"
    end = next((i for i in range(sec + 1, len(lines)) if lines[i].startswith("[")), len(lines))
    ins = next((i for i in range(sec, end) if re.match(r"^insert_gcode\s*:", lines[i])), None)
    if ins is None: return text, "NOANCHOR"
    # block = indented or blank lines after insert_gcode:, until the next option/section
    b_end = ins + 1
    while b_end < end and (lines[b_end].startswith((" ", "\t")) or not lines[b_end].strip()): b_end += 1
    block = range(ins + 1, b_end)
    head, grab, done = "_WM_ACE_HEAD T=%d" % n, "_WM_ACE_GRAB T=%d" % n, "_WM_ACE_HEAD_DONE T=%d" % n
    has = lambda w: any(lines[i].strip() == w for i in block)
    fi = next((i for i in block if re.match(r"^\s+filament_insert\s*$", lines[i])), None)
    pk = next((i for i in block if re.match(r"^\s+PARK_CURRENT_TOOL\s*$", lines[i])), None)
    first = next((i for i in block if lines[i].strip()), None)
    if first is None or fi is None or pk is None: return text, "NOANCHOR"
    out = list(lines); changed = False
    # insert from the bottom up so indexes stay valid
    if not has(done):
        out.insert(pk + 1, re.match(r"^(\s+)", lines[pk]).group(1) + done); changed = True
    if not has(grab):
        out.insert(fi, re.match(r"^(\s+)", lines[fi]).group(1) + grab); changed = True
    if not has(head):
        out.insert(first, "    " + head); changed = True
    return "\n".join(out), ("ADDED" if changed else "OK")


def strip(text, n):
    mine = {"_WM_ACE_HEAD T=%d" % n, "_WM_ACE_GRAB T=%d" % n, "_WM_ACE_HEAD_DONE T=%d" % n}
    keep = [l for l in text.split("\n") if l.strip() not in mine]
    return "\n".join(keep), len(keep) != len(text.split("\n"))


def main(argv):
    if len(argv) != 3 or argv[1] not in ("check", "apply", "remove"): print(__doc__); return 2
    mode, d = argv[1], argv[2]; bad = 0
    for n in range(4):
        p = os.path.join(d, "extruder%d.cfg" % n)
        if not os.path.isfile(p): print("extruder%d.cfg NOFILE" % n); bad = 1; continue
        text = open(p, encoding="utf-8", errors="surrogateescape").read()
        if mode == "remove":
            new, ch = strip(text, n)
            if ch: open(p, "w", encoding="utf-8", errors="surrogateescape").write(new)
            print("extruder%d.cfg %s" % (n, "REMOVED" if ch else "OK")); continue
        new, st = process(text, n)
        if st == "NOANCHOR": print("extruder%d.cfg NOANCHOR" % n); bad = 1; continue
        if mode == "check":
            print("extruder%d.cfg %s" % (n, "MISSING" if st == "ADDED" else "OK"))
            bad |= (st == "ADDED")
        else:
            if st == "ADDED": open(p, "w", encoding="utf-8", errors="surrogateescape").write(new)
            print("extruder%d.cfg %s" % (n, st))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
