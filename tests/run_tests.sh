#!/bin/bash
# Installer tests for the WonderMaker Ultra installer. They run installer.sh against FAKE
# home folders in /tmp, answer its questions through stdin, and never touch a printer, service or real config.
#
#   bash tests/run_tests.sh
#
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INST="$REPO/installer.sh"
PASS=0; FAIL=0
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

ok()   { PASS=$((PASS+1)); echo "  ok    $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL  $1"; [ -n "${2:-}" ] && echo "$2" | sed 's/^/        /' | head -25; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }

new_home() { # name [nowm]
    local h="$ROOT/$1" c
    c="$h/printer_data/config"
    mkdir -p "$h/klipper/klippy/extras" "$c" "$h/printer_data/logs" "$h/fluidd/assets"
    echo '{"x":1}' > "$h/fluidd/config.json"; echo old > "$h/fluidd/assets/old.js"
    printf '[include mainsail.cfg]\n[include zru-s.cfg]\n[include other.cfg]\n\n[save_variables]\nfilename: /tmp/v.cfg\n\n[respond]\n\n#*# <---------------------- SAVE_CONFIG ---------------------->\n#*# DO NOT EDIT THIS BLOCK OR BELOW. The contents are auto-generated.\n#*#\n#*# [heater_bed]\n#*# control = pid\n' > "$c/printer.cfg"
    if [ "${2:-}" != nowm ]; then
        printf '[gcode_macro _CHANGE_TOOL]\ngcode:\n\n[gcode_macro UNLOAD_FILAMENT]\ngcode:\n\n[filament_switch_sensor path_0]\nswitch_pin: !HUB:PC13\n' > "$c/zru-s.cfg"
    fi
    echo "$h"
}
inst() { # home answers [args...]
    local h="$1" answers="$2"; shift 2
    OUT="$(printf '%b' "$answers" | ACE_INSTALL_HOME="$h" ACE_INSTALLER_TEST=1 bash "$INST" "$@" 2>&1)"; RC=$?
}
cfg() { echo "$1/printer_data/config"; }

# Answers in order: ACE Pro? auto-load? endless? Fluidd panel? continue?
A_ALL='y\ny\ny\ny\ny\n'

echo "1. Fresh install"
H="$(new_home t1)"; C="$(cfg "$H")"
inst "$H" "$A_ALL"
check "installer finished"                          test "$RC" -eq 0
for f in wm_ace_driver.cfg wm_ace.cfg wm_endless.cfg wm-ultra-install.conf; do check "$f written" test -f "$C/$f"; done
check "includes sit right after zru-s.cfg"          test "$(sed -n 3,5p "$C/printer.cfg" | tr '\n' ' ')" = "[include wm_ace_driver.cfg] [include wm_ace.cfg] [include wm_endless.cfg] "
check "other.cfg include still follows"             test "$(sed -n 6p "$C/printer.cfg")" = "[include other.cfg]"
check "SAVE_CONFIG block untouched"                 test "$(tail -1 "$C/printer.cfg")" = "#*# control = pid"
check "register_tool_commands False kept"           grep -q '^register_tool_commands: False' "$C/wm_ace_driver.cfg"
check "auto-load = 1"                               grep -q '^variable_auto: *1' "$C/wm_ace.cfg"
check "driver linked to the repo"                   test "$(readlink "$H/klipper/klippy/extras/ace")" = "$REPO/extras/ace"
check "virtual_pins linked"                         test -L "$H/klipper/klippy/extras/virtual_pins.py"
check "temperature_ace linked"                      test -L "$H/klipper/klippy/extras/temperature_ace.py"
check "Fluidd has the panel"                        grep -rlq "ACE feeder" "$H/fluidd/assets"
check "Fluidd config.json kept"                     grep -q '"x":1' "$H/fluidd/config.json"
check "Fluidd backup folder exists"                 test -n "$(ls -d "$H"/fluidd_backup_* 2>/dev/null)"
check "backup manifest exists"                      test -n "$(ls "$H"/acepro-backup/wm-*/manifest.txt 2>/dev/null)"
check "no WonderMaker file was edited"              grep -q '^\[gcode_macro _CHANGE_TOOL\]' "$C/zru-s.cfg"
check "Klipper was not restarted"                   bash -c '! echo "$0" | grep -q "Klipper restarted\."' "$OUT"
inst "$H" "" --check;  check "--check passes"       test "$RC" -eq 0

echo "2. Update keeps tuned values"
sed -i 's/^variable_hub_to_head_mm: *900/variable_hub_to_head_mm: 1234/;s/^variable_auto: *1/variable_auto: 0/' "$C/wm_ace.cfg"
sed -i 's/^feed_speed: 60/feed_speed: 33/' "$C/wm_ace_driver.cfg"
inst "$H" 'n\ny\n' --update
check "update finished"                             test "$RC" -eq 0
check "hub_to_head_mm 1234 kept"                    grep -q '^variable_hub_to_head_mm: *1234' "$C/wm_ace.cfg"
check "auto 0 kept"                                 grep -q '^variable_auto: *0' "$C/wm_ace.cfg"
check "feed_speed 33 kept"                          grep -q '^feed_speed: *33' "$C/wm_ace_driver.cfg"
check "includes not duplicated"                     test "$(grep -c 'include wm_ace.cfg' "$C/printer.cfg")" -eq 1

echo "3. Dry run changes nothing"
H3="$(new_home t3)"; C3="$(cfg "$H3")"; cp -a "$C3/printer.cfg" "$ROOT/p3.cfg"
inst "$H3" "$A_ALL" --dry-run
check "dry run finished"                            test "$RC" -eq 0
check "printer.cfg identical"                       cmp -s "$ROOT/p3.cfg" "$C3/printer.cfg"
check "no ACE cfg written"                          test ! -e "$C3/wm_ace.cfg"
check "no link made"                                test ! -e "$H3/klipper/klippy/extras/ace"

echo "4. Not a WonderMaker config"
H4="$(new_home t4 nowm)"
inst "$H4" "$A_ALL"
check "refuses with exit 1"                         test "$RC" -eq 1
check "says why"                                    bash -c 'echo "$0" | grep -q "does not look like a WonderMaker"' "$OUT"
check "nothing written"                             test ! -e "$(cfg "$H4")/wm_ace.cfg"

echo "5. Print in progress"
H5="$(new_home t5)"
OUT="$(printf '%b' "$A_ALL" | ACE_PRINT_STATE=printing ACE_INSTALL_HOME="$H5" ACE_INSTALLER_TEST=1 bash "$INST" 2>&1)"; RC=$?
check "refuses while printing"                      test "$RC" -eq 1
check "nothing written"                             test ! -e "$(cfg "$H5")/wm_ace.cfg"

echo "6. Without endless spool and without Fluidd"
H6="$(new_home t6)"; C6="$(cfg "$H6")"
inst "$H6" 'y\ny\nn\nn\ny\n'
check "installer finished"                          test "$RC" -eq 0
check "wm_endless.cfg not written"                  test ! -e "$C6/wm_endless.cfg"
check "no endless include"                          bash -c '! grep -q wm_endless "$0"' "$C6/printer.cfg"
check "Fluidd untouched"                            bash -c '! grep -rq "ACE feeder" "$0"' "$H6/fluidd/assets"
inst "$H6" "" --check;  check "--check passes"      test "$RC" -eq 0

echo "7. Undo restores everything"
H7="$(new_home t7)"; C7="$(cfg "$H7")"; cp -a "$C7/printer.cfg" "$ROOT/p7.cfg"
inst "$H7" "$A_ALL"
inst "$H7" 'y\n' --undo
check "undo finished"                               test "$RC" -eq 0
check "printer.cfg back to the original"            cmp -s "$ROOT/p7.cfg" "$C7/printer.cfg"
check "ACE cfgs gone"                               test ! -e "$C7/wm_ace.cfg"
check "link gone"                                   test ! -e "$H7/klipper/klippy/extras/ace"
check "Fluidd back to the old build"                test -f "$H7/fluidd/assets/old.js"

echo "8. Uninstall, then undo"
H8="$(new_home t8)"; C8="$(cfg "$H8")"; cp -a "$C8/printer.cfg" "$ROOT/p8.cfg"
inst "$H8" "$A_ALL"
inst "$H8" 'y\n' --uninstall
check "uninstall finished"                          test "$RC" -eq 0
check "includes removed"                            bash -c '! grep -q "wm_ace" "$0"' "$C8/printer.cfg"
check "cfgs removed"                                test ! -e "$C8/wm_ace.cfg"
check "links removed"                               test ! -e "$H8/klipper/klippy/extras/ace"
inst "$H8" 'y\n' --undo
check "undo after uninstall brings cfgs back"       test -f "$C8/wm_ace.cfg"

echo "9. Repair"
H9="$(new_home t9)"; C9="$(cfg "$H9")"
inst "$H9" "$A_ALL"
rm -f "$H9/klipper/klippy/extras/ace"; sed -i '/wm_ace.cfg/d' "$C9/printer.cfg"
inst "$H9" "" --check;  check "--check finds the damage"  test "$RC" -ne 0
inst "$H9" "" --repair; check "--repair finished"          test "$RC" -eq 0
inst "$H9" "" --check;  check "--check passes again"       test "$RC" -eq 0

echo "10. No ACE Pro (panel + endless spool only)"
H10="$(new_home t10)"; C10="$(cfg "$H10")"; cp -a "$C10/printer.cfg" "$ROOT/p10.cfg"
inst "$H10" 'n\ny\ny\ny\n'
check "installer finished"                          test "$RC" -eq 0
check "wm_endless.cfg written"                      test -f "$C10/wm_endless.cfg"
check "no ACE cfgs"                                 test ! -e "$C10/wm_ace.cfg" -a ! -e "$C10/wm_ace_driver.cfg"
check "only the endless include added"              bash -c 'grep -q "include wm_endless.cfg" "$0" && ! grep -q "wm_ace" "$0"' "$C10/printer.cfg"
check "driver not linked"                           test ! -e "$H10/klipper/klippy/extras/ace"
check "Fluidd has the panel"                        grep -rlq "ACE feeder" "$H10/fluidd/assets"
check "conf says ACE=0"                             grep -q '^ACE="0"' "$C10/wm-ultra-install.conf"
inst "$H10" "" --check;  check "--check passes"     test "$RC" -eq 0
inst "$H10" 'n\n' --update; check "update keeps panel-only mode" bash -c '! test -e "$0/wm_ace.cfg"' "$C10"
inst "$H10" 'y\n' --uninstall; check "uninstall finished"  test "$RC" -eq 0
check "printer.cfg back to the original"            cmp -s "$ROOT/p10.cfg" "$C10/printer.cfg"
H11="$(new_home t11)"
inst "$H11" 'n\nn\nn\n'
check "nothing selected is refused"                 test "$RC" -eq 1

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
