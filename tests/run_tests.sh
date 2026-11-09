#!/bin/bash
# Installer tests for the WonderMaker Ultra installer. They run installer.sh against FAKE
# home folders in /tmp, answer its questions through stdin, and never touch a printer, service or real config.
#
#   bash tests/run_tests.sh
#
set -u
if [ -z "${ACE_TESTS_IN_COPY:-}" ]; then   # always test a throwaway copy of the repository, never the real folder
    CP="$(mktemp -d)"; cp -a "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/." "$CP/"
    ACE_TESTS_IN_COPY=1 bash "$CP/tests/run_tests.sh" "$@"; rc=$?; rm -rf "$CP"; exit $rc
fi
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
check "includes sit after [save_variables], above SAVE_CONFIG" test "$(grep -n 'include wm_\|save_variables\|SAVE_CONFIG' "$C/printer.cfg" | cut -d: -f2- | tr '\n' ' ')" = "[save_variables] [include wm_ace_driver.cfg] [include wm_ace.cfg] [include wm_endless.cfg] [include wm_stats.cfg] #*# <---------------------- SAVE_CONFIG ----------------------> "
check "other.cfg include still follows zru-s"        test "$(sed -n 2,3p "$C/printer.cfg" | tr '\n' ' ')" = "[include zru-s.cfg] [include other.cfg] "
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
for n in 1 2 3 4 5 6 7; do mkdir -p "$H/fluidd_backup_2020010$n" "$H/acepro-backup/wm-2020010${n}_000000"; touch -d "2020-01-0$n" "$H/fluidd_backup_2020010$n" "$H/acepro-backup/wm-2020010${n}_000000"; done
inst "$H" "$A_ALL"
check "old saved copies: only the newest 5 stay, the newest is kept" bash -c "[ \$(ls -d '$H'/fluidd_backup_* | wc -l) -le 5 ] && [ \$(ls -d '$H'/acepro-backup/wm-*/ | wc -l) -le 5 ] && [ -d '$H/acepro-backup/wm-20200107_000000' ] && [ ! -d '$H/acepro-backup/wm-20200101_000000' ]"
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
check "uninstall put the original Fluidd back"      test -f "$H8/fluidd/assets/old.js"
check "uninstall: panel gone from Fluidd"           bash -c '! grep -rq "ACE feeder" "$0"' "$H8/fluidd/assets"
check "uninstall kept Fluidd config.json"           grep -q '"x":1' "$H8/fluidd/config.json"
check "original Fluidd copy was saved for good"     test -f "$H8/acepro-backup/original-fluidd/assets/old.js"
inst "$H8" 'y\n' --undo
check "undo after uninstall brings cfgs back"       test -f "$C8/wm_ace.cfg"
check "undo after uninstall brings the panel back"  grep -rlq "ACE feeder" "$H8/fluidd/assets"
for n in 1 2 3 4 5 6 7; do mkdir -p "$H8/fluidd_backup_2020010$n"; touch -d "2020-01-0$n" "$H8/fluidd_backup_2020010$n"; done
inst "$H8" "$A_ALL"
check "original Fluidd copy survives pruning"       test -f "$H8/acepro-backup/original-fluidd/assets/old.js"
check "original Fluidd copy is not overwritten"     bash -c '! grep -rq "ACE feeder" "$0"' "$H8/acepro-backup/original-fluidd/assets"

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
check "wm_stats.cfg written (counters, tool map)"    test -f "$C10/wm_stats.cfg"
check "only endless and stats includes added"       bash -c 'grep -q "include wm_endless.cfg" "$0" && grep -q "include wm_stats.cfg" "$0" && ! grep -q "wm_ace" "$0"' "$C10/printer.cfg"
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
echo "Menu"
HM="$(new_home tm)"
menu() { OUT="$(printf '%b' "$1" | ACE_INSTALL_HOME="$HM" ACE_INSTALLER_TEST=1 ACE_MENU_TEST=1 ACE_TEST_NEW_VERSION="${2:-}" bash "$INST" 2>&1)"; RC=$?; }
menu '0\n'
check "menu opens with no options"                  bash -c 'echo "$0" | grep -q "6) Uninstall"' "$OUT"
check "menu has Update and Dry run"                 bash -c 'echo "$0" | grep -q "2) Update" && echo "$0" | grep -q "5) Dry run"' "$OUT"
menu '2\n1\n0\n0\n0\n' 9.9.9
check "see what is new shows both versions"         bash -c 'echo "$0" | grep -q "newest on GitHub: v9.9.9"' "$OUT"
menu '3\n1\n0\n0\n0\n'
check "menu check runs"                             bash -c 'echo "$0" | grep -q "ACE Pro check"' "$OUT"
menu '4\n1\n0\n0\n'
check "backup menu says no backups"                 bash -c 'echo "$0" | grep -q "No backups yet"' "$OUT"
menu '9\n0\n'
check "bad number is refused"                       bash -c 'echo "$0" | grep -q "Choose a number"' "$OUT"
menu '5\ny\ny\ny\ny\ny\n0\n'
check "menu dry run changes nothing"                test ! -e "$(cfg "$HM")/wm_ace.cfg"
OUT="$(printf '' | bash "$INST" 2>&1 </dev/null)"
check "no terminal and no options does not hang on a menu" bash -c '! echo "$0" | grep -q "6) Uninstall"' "$OUT"
GL="$ROOT/gl"; mkdir -p "$GL/src"; cp "$REPO/installer.sh" "$GL/src/"; echo 7.7.7 > "$GL/src/VERSION"; tar -czf "$GL/t.tgz" -C "$GL" src
cp -a "$REPO" "$ROOT/copy"; rm -rf "$ROOT/copy/.git"
OUT="$(ACE_TEST_TARBALL="$GL/t.tgz" ACE_INSTALLER_TEST=1 bash "$ROOT/copy/installer.sh" --get-latest 2>&1)"
check "--get-latest without git refreshes the folder" test "$(tr -d '[:space:]' < "$ROOT/copy/VERSION")" = 7.7.7

OUT="$(printf '2\n2\nn\nn\nn\nn\n0\n' | ACE_TEST_TARBALL="$GL/t.tgz" ACE_MENU_TEST=1 ACE_INSTALLER_TEST=1 ACE_INSTALL_HOME="$HM" bash "$ROOT/copy/installer.sh" 2>&1)"
check "Update now restarts the menu on the new version" bash -c 'echo "$0" | grep -q "installer v7.7.7"' "$OUT"
OUT="$(printf '2\n2\n0\n0\n' | ACE_TEST_TARBALL="$GL/t.tgz" ACE_MENU_TEST=1 ACE_INSTALLER_TEST=1 ACE_INSTALL_HOME="$ROOT/emptyhome" bash "$ROOT/copy/installer.sh" 2>&1)"
check "Update now with nothing installed explains it instead of a red error" bash -c 'echo "$0" | grep -q "Nothing is installed on this machine yet" && ! echo "$0" | grep -q "Can.t continue"' "$OUT"
echo
echo "Factory screen board: clock and apt"
HF="$(new_home tf)"
inst() { local h="$1" answers="$2"; shift 2
    OUT="$(printf '%b' "$answers" | ACE_INSTALL_HOME="$h" ACE_INSTALLER_TEST=1 ${ACE_TEST_FACTORY_BOARD:+ACE_TEST_FACTORY_BOARD=$ACE_TEST_FACTORY_BOARD} bash "$INST" "$@" 2>&1)"; RC=$?; }
inst "$HF" "$A_ALL"
check "not a factory board: no clock or apt step"   bash -c '! echo "$0" | grep -q "factory screen board"; ! test -f "$1/.sudo.log"' "$OUT" "$HF"
HG="$(new_home tg)"
OUT="$(printf '%b' "y\n$A_ALL" | ACE_TEST_FACTORY_BOARD=1 ACE_INSTALL_HOME="$HG" ACE_INSTALLER_TEST=1 bash "$INST" 2>&1)"
check "factory board: the clock and apt step runs"  bash -c 'echo "$0" | grep -q "This is the factory screen board"' "$OUT"
check "factory board: NTP turned on"                grep -q "timedatectl set-ntp true" "$HG/.sudo.log"
check "factory board: apt date check switched off"  grep -q "99no-check-valid-until" "$HG/.sudo.log"
HH="$(new_home th)"
OUT="$(printf '%b' "$A_ALL" | ACE_TEST_NTP_SYNCED=yes ACE_TEST_FACTORY_BOARD=1 ACE_INSTALL_HOME="$HH" ACE_INSTALLER_TEST=1 bash "$INST" --dry-run 2>&1)"
check "factory board dry run changes nothing"       bash -c '! grep -q "timedatectl" "$0/.sudo.log" 2>/dev/null' "$HH"
OUT="$(ACE_INSTALL_HOME="$HH" ACE_INSTALLER_TEST=1 bash "$INST" --fix-clock 2>&1)"
check "--fix-clock elsewhere says nothing to fix"   bash -c 'echo "$0" | grep -q "nothing to fix"' "$OUT"
echo
echo "Free up disk space"
FB="$ROOT/fsb"; FT="$ROOT/fst"; mkdir -p "$FB/.cache/pip" "$FB/printer_data/logs" "$FB/printer_data/gcodes" "$FT/tmp.AAA/orca_plugin" "$FT/tmp.keep"
dd if=/dev/zero of="$FB/.cache/pip/x" bs=1M count=3 2>/dev/null; dd if=/dev/zero of="$FT/tmp.AAA/pad" bs=1M count=3 2>/dev/null
echo 1.0.0 > "$FT/tmp.AAA/VERSION"; touch "$FT/tmp.AAA/installer.sh"; echo mine > "$FT/tmp.keep/file"; echo gcode > "$FB/printer_data/gcodes/a.gcode"
dd if=/dev/zero of="$FB/printer_data/logs/klippy.log.1" bs=1M count=2 2>/dev/null
fsx() { local ans="$1"; shift; printf "$ans" | ACE_TEST_TMP="$FT" ACE_INSTALL_HOME="$FB" ACE_INSTALLER_TEST=1 ACE_TEST_APT_KB=204800 ACE_TEST_JOURNAL_KB=102400 "$@" bash "$INST" --free-space 2>&1; }
fsx '\n' env > "$ROOT/fs1.out"
check "free space: lists what can go, with sizes and warnings" bash -c 'grep -q "Leftover installer downloads" "$0" && grep -q "apt package cache" "$0" && grep -q "Old rotated printer logs" "$0" && grep -q "never in this list" "$0"' "$ROOT/fs1.out"
check "free space: Enter cancels and erases nothing" bash -c '[ -d "$0/tmp.AAA" ] && [ -d "$1/.cache/pip" ]' "$FT" "$FB"
fsx '1\nn\n' env > "$ROOT/fs2.out"
check "free space: warning and 'This will ERASE' before the confirmation; no erases nothing" bash -c 'grep -q "This will ERASE" "$0" && grep -q "Copies of this installer" "$0" && [ -d "$1/tmp.AAA" ]' "$ROOT/fs2.out" "$FT"
fsx '1\ny\n' env >/dev/null
check "free space: erases only the chosen item after confirming" bash -c '[ ! -d "$0/tmp.AAA" ] && [ -d "$0/tmp.keep" ] && [ -d "$1/.cache/pip" ] && [ -f "$1/printer_data/gcodes/a.gcode" ]' "$FT" "$FB"
fsx 'all\ny\n' env >/dev/null
check "free space: all uses sudo for apt and the journal, keeps gcode and the real repository" bash -c 'grep -q "apt-get clean" "$0/.sudo.log" && grep -q "vacuum-size=50M" "$0/.sudo.log" && [ ! -d "$0/.cache/pip" ] && [ ! -f "$0/printer_data/logs/klippy.log.1" ] && [ -f "$0/printer_data/gcodes/a.gcode" ] && [ -d "$1/.git" -o ! -e "$1/.git" ]' "$FB" "$REPO"
check "free space: the menu has the entry"        bash -c 'printf "7\n0\n0\n" | ACE_MENU_TEST=1 ACE_INSTALLER_TEST=1 ACE_INSTALL_HOME="$0" bash "$1" 2>&1 | grep -q "Free up disk space"' "$FB" "$INST"
HL="$(new_home tl)"
OUT="$(ACE_TEST_DISK_MB=100 ACE_INSTALL_HOME="$HL" ACE_INSTALLER_TEST=1 bash "$INST" </dev/null 2>&1)"
check "install: not enough space and no terminal stops with the --free-space hint" bash -c 'echo "$0" | grep -q "free-space"' "$OUT"
HM2="$(new_home tm2)"; mkdir -p "$HM2/.cache/pip"; dd if=/dev/zero of="$HM2/.cache/pip/x" bs=1M count=3 2>/dev/null; mkdir -p "$FT/tmp.AAA/orca_plugin"; dd if=/dev/zero of="$FT/tmp.AAA/pad" bs=1M count=3 2>/dev/null; echo 1 > "$FT/tmp.AAA/VERSION"; touch "$FT/tmp.AAA/installer.sh"
OUT="$(printf 'y\n1\ny\n%b' "$A_ALL" | ACE_TEST_FREE_OFFER=1 ACE_TEST_DISK_MB=299 ACE_TEST_TMP="$FT" ACE_INSTALL_HOME="$HM2" ACE_INSTALLER_TEST=1 bash "$INST" 2>&1)"
check "install: not enough space offers the cleanup, warns, then goes on" bash -c 'echo "$0" | grep -q "Only 299 MB free" && echo "$0" | grep -q "This will ERASE" && echo "$0" | grep -q "Disk space ok"' "$OUT"
echo
echo "Doctor, support bundle and progress bars"
DH="$(new_home doc)"
inst "$DH" "$A_ALL"
check "install shows a progress bar that reaches 100 percent" bash -c 'echo "$0" | grep -q "100%  Done"' "$OUT"
check "install bar names its steps"                 bash -c 'echo "$0" | grep -q "Step 3 of 5"' "$OUT"
inst "$DH" "" --doctor
check "doctor on a healthy install finds nothing"   bash -c 'echo "$0" | grep -q "No problems found"' "$OUT"
rm -f "$(cfg "$DH")/wm_ace.cfg"
inst "$DH" "n\n" --doctor
check "doctor reports the missing file" bash -c 'echo "$0" | grep -q "are missing"' "$OUT"
check "doctor changes nothing when you say no"      test ! -e "$(cfg "$DH")/wm_ace.cfg"
inst "$DH" "y\n" --doctor
check "doctor restores the file when you say yes"   test -e "$(cfg "$DH")/wm_ace.cfg"
echo "password: hunter2 on 192.168.1.50" >> "$(cfg "$DH")/moonraker.conf"
inst "$DH" "" --support-bundle
check "support bundle is written"                   bash -c 'ls "$0"/ace-support-*.tgz' "$DH"
BX="$ROOT/bx"; mkdir -p "$BX"; tar xzf "$DH"/ace-support-*.tgz -C "$BX"
check "support bundle report has the USB tree and serial port sections" bash -c 'grep -q "usb tree" "$0/ace-support/system.txt" && grep -q "serial ports the ACE driver sees" "$0/ace-support/system.txt"' "$BX"
check "support bundle removes passwords and private addresses" bash -c '! grep -rq "hunter2\|192.168.1.50" "$0"' "$BX"
check "support bundle has the system report and configs" bash -c 'test -s "$0/ace-support/system.txt" && test -s "$0/ace-support/config/printer.cfg"' "$BX"
menu '3\n3\n0\n0\n0\n'
check "check and fix menu has Doctor and Support bundle" bash -c 'echo "$0" | grep -q "3) Doctor" && echo "$0" | grep -q "4) Support bundle"' "$OUT"

echo "Progress bar never gets in the way of a question"
bar_check() {   # script-with-progress_bar : the bar is printed once, never redrawn, and no background job is started
    local LB; LB="$(mktemp -d)"
    cat > "$LB/lt.sh" <<EOT
GREEN=; NC=; TESTING=0; DRY=0
eval "\$(sed -n '/^prog_repeat()/p;/^progress_bar()/,/^}/p' $1)"
progress_bar 1 5 "Step 2 of 5"; read -r -p "question? " a; echo "[\$a]"; sleep 2; jobs -p | wc -l
EOT
    python3 - "$LB/lt.sh" <<'EOP'
import pty,os,struct,fcntl,termios,time,sys
pid,fd=pty.fork()
if pid==0: os.execvp('bash',['bash',sys.argv[1]])
fcntl.ioctl(fd,termios.TIOCSWINSZ,struct.pack('HHHH',24,80,0,0))
out=b''; t=time.time(); sent=False
while time.time()-t<6:
    try: d=os.read(fd,4096)
    except OSError: break
    if not d: break
    out+=d
    if b'question?' in out and not sent: time.sleep(1.2); os.write(fd,b'hello\n'); sent=True
sys.exit(0 if out.count(b'Step 2 of 5')==1 and b'\x1b[' not in out.replace(b'\x1b[0m',b'').replace(b'\x1b[0;32m',b'') and b'[hello]' in out and b'\n0' in out.replace(b'\r',b'') else 1)
EOP
}
check "fluidd installer: the bar is printed once and a question after it stays clean" bar_check $INST
check "get-latest: the download in /tmp is removed on Ctrl-C" grep -qF 'trap '"'"'rm -rf "$tmp"; exit 130'"'"' INT TERM' "$INST"
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
