#!/bin/bash

# =============================================================================
# ACE Pro on the WonderMaker ZR Ultra / Ultra-S  -  installer
# =============================================================================
# Adds the WonderMaker Toolheads panel and, if you have one, an Anycubic ACE Pro (feeder + dryer)
# to the machine that runs WonderMaker's own Klipper / Moonraker / Fluidd. Without an ACE Pro it
# installs only the panel (and the optional endless-spool macros).
#
# ./installer.sh               install (asks a few plain questions first)
# ./installer.sh --update      update the files, keep your tuned values
# ./installer.sh --check       report problems, change nothing
# ./installer.sh --repair      restore links and include lines
# ./installer.sh --doctor      find problems and offer a fix for each (asks first)
# ./installer.sh --support-bundle  make a scrubbed .tgz of logs and config to share when asking for help
# ./installer.sh --undo [DIR]  put back the files saved before the last install
# ./installer.sh --uninstall   remove everything the installer added (saved first, --undo brings it back)
# ./installer.sh --fix-clock   factory screen board only: automatic time sync (NTP) and apt (Debian archive)
# ./installer.sh --free-space  list what is safe to erase (sizes, warnings), erase what you pick and confirm
# ./installer.sh --menu        numbered menu (this is what you get with no options at a terminal)
# ./installer.sh --install     install without the menu
# ./installer.sh --check-updates  see what is new on GitHub (changes nothing)
# ./installer.sh --get-latest  download the newest installer files (git pull, or a tarball without git)
# ./installer.sh --dry-run     go through the questions, show what would change, change nothing
# ./installer.sh --help
#
# What this installer never does:
#   - It never flashes any board (main board, toolheads, hub). No firmware is touched.
#   - It never starts or restarts Klipper unless you answer yes to that one question.
#   - It never changes a WonderMaker file. Your printer.cfg only gets up to four include lines.
#
# Needs bash and python3 (Debian based systems).
# =============================================================================

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"   # repo root
REPO_DIR="$SCRIPT_DIR"                                          # repo root (extras/ace lives here)
VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION" 2>/dev/null || true)"
VERSION="${VERSION:-dev}"

INSTALL_USER="${SUDO_USER:-$(id -un)}"
INSTALL_HOME="$(getent passwd "$INSTALL_USER" 2>/dev/null | cut -d: -f6 || true)"
[ -n "$INSTALL_HOME" ] || INSTALL_HOME="$HOME"
INSTALL_HOME="${ACE_INSTALL_HOME:-$INSTALL_HOME}"

TESTING="${ACE_INSTALLER_TEST:-0}"          # 1 = never restart services, never touch pip
MODE="install"
DRY=0
UNDO_ARG=""
KLIPPER_DIR="${ACE_KLIPPER_DIR:-}"
CONFIG_DIR="${ACE_CONFIG_DIR:-}"
BACKUP_ROOT="$INSTALL_HOME/acepro-backup"
MOONRAKER_URL="http://127.0.0.1:7125"
KLIPPER_SERVICE="klipper"
CONF_NAME="wm-ultra-install.conf"

# Answers
HAVE_ACE=1                                  # 0 = no ACE Pro: panel (and optional endless spool) only
WANT_AUTO=1
WANT_FLUIDD=0
WANT_ENDLESS=1
FLUIDD_DIR=""
UPDATING=0
OLD_VERSION=""
STAGE=""
BACKUP_DIR=""
declare -a WARNINGS=()

CFG_FILES=(wm_ace_driver.cfg wm_ace.cfg wm_endless.cfg wm_stats.cfg)
INCLUDE_LINES=("[include wm_ace_driver.cfg]" "[include wm_ace.cfg]" "[include wm_endless.cfg]" "[include wm_stats.cfg]")
# Values the installer keeps when you update (file:key). "var" keys are `variable_<key>:` lines, "opt" keys are `<key>:` lines.
KEEP_VARS_ACE=(max_total_mm hub_to_head_mm tail_mm fast_speed slow_speed retract_speed tick_s fast_timeout_s slow_timeout_s auto)
KEEP_VARS_ENDLESS=(hop prime_mm prime_speed)
KEEP_OPTS_DRIVER=(feed_speed retract_speed max_dryer_temperature moonraker_lane_sync_enabled)

# ============================================================================
# Output helpers
# ============================================================================

print_header()  { echo -e "\n${BLUE}── $1 ──────────────────────────────────────────${NC}"; }
print_info()    { echo -e "${BLUE}ℹ ${1}${NC}"; }
print_success() { echo -e "${GREEN}✓ ${1}${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ ${1}${NC}"; }
print_error()   { echo -e "${RED}✗ ${1}${NC}"; }
why()           { echo -e "  ${DIM}Why: $1${NC}"; }
warn_later()    { WARNINGS+=("$1"); }
prog_repeat()   { local i out=""; for ((i=0;i<$2;i++)); do out+="$1"; done; printf '%s' "$out"; }
progress_bar() {   # steps-done total label : a bar like [██████░░░░░░]  42%  label
    local n="$1" t="$2" label="${3:-}" w=24 f pct
    [ "$t" -gt 0 ] 2>/dev/null || return 0
    [ "$n" -gt "$t" ] && n="$t"; [ "$n" -lt 0 ] && n=0
    pct=$((n*100/t)); f=$((n*w/t))
    printf '  %b[%s%s]%b %3d%%  %s\n' "$GREEN" "$(prog_repeat '█' "$f")" "$(prog_repeat '░' $((w-f)))" "$NC" "$pct" "$label"
}
live_bar_stop() { return 0; }   # (the bar is printed once per step; it never redraws, so it cannot get in the way of a question)

die_with_fix() {
    local msg="$1" fix="$2"
    live_bar_stop
    print_error "Can't continue: $msg"
    [ -n "$fix" ] && echo -e "  Fix: $fix"
    echo "  Nothing was changed."
    exit 1
}

cleanup() { [ -n "${STAGE:-}" ] && [ -d "$STAGE" ] && rm -rf "$STAGE"; return 0; }
trap cleanup EXIT

# ============================================================================
# Questions
# ============================================================================

ask_yn() { # "Question" Y|N ["why"]
    local q="$1" def="${2:-N}" w="${3:-}" hint ans
    [ -n "$w" ] && why "$w"
    if [ "$def" = "Y" ]; then hint="[Y/n]"; else hint="[y/N]"; fi
    while true; do
        read -r -p "$(echo -e "${BLUE}${q}${NC} ${hint}: ")" ans || ans=""
        ans="${ans:-$def}"
        case "$ans" in
            [yY]*) return 0 ;;
            [nN]*) return 1 ;;
            *) echo "  Please answer y or n" ;;
        esac
    done
}

timestamp() { date +"%Y%m%d_%H%M%S"; }
prune_backups() {   # keeps the newest 5 saved copies of Fluidd and the newest 5 backup folders; older ones are deleted (the newest always stays, so --undo still works)
    local o
    [ -n "${1:-}" ] && ls -1dt "$1"_backup_* 2>/dev/null | tail -n +6 | while read -r o; do rm -rf "$o"; done
    ls -1dt "$BACKUP_ROOT"/wm-*/ 2>/dev/null | tail -n +6 | while read -r o; do rm -rf "$o"; done
}
is_symlink() { [ -L "$1" ]; }
CONF_FILE() { echo "$CONFIG_DIR/$CONF_NAME"; }

kv_get() { # file key
    [ -f "$1" ] || return 1
    sed -n "s/^$2=\"\{0,1\}\(.*[^\"]\)\"\{0,1\}$/\1/p" "$1" | head -1
}

klippy_python() {
    if [ -x "$INSTALL_HOME/klippy-env/bin/python" ]; then echo "$INSTALL_HOME/klippy-env/bin/python"; else echo python3; fi
}

# ============================================================================
# Backup (same manifest format as the ACE Pro installer)
# ============================================================================

backup_path() {
    local p="$1"
    [ -n "$BACKUP_DIR" ] || return 0
    grep -qxF -e "MOD $p" -e "NEW $p" "$BACKUP_DIR/manifest.txt" 2>/dev/null && return 0
    if [ -e "$p" ] || is_symlink "$p"; then
        mkdir -p "$BACKUP_DIR/files$(dirname "$p")"
        cp -a "$p" "$BACKUP_DIR/files$p" 2>/dev/null
        echo "MOD $p" >> "$BACKUP_DIR/manifest.txt"
    else
        echo "NEW $p" >> "$BACKUP_DIR/manifest.txt"
    fi
}

# ============================================================================
# Checks
# ============================================================================

print_state() { # -> printing|paused|standby|... (empty if Moonraker cannot be reached)
    [ -n "${ACE_PRINT_STATE:-}" ] && { echo "$ACE_PRINT_STATE"; return 0; }
    [ "$TESTING" = 1 ] && { echo ""; return 0; }
    curl -s -m 3 "$MOONRAKER_URL/printer/objects/query?print_stats" 2>/dev/null | \
        python3 -I -c 'import sys,json; print(json.load(sys.stdin)["result"]["status"]["print_stats"]["state"])' 2>/dev/null || echo ""
}

guard_not_printing() {
    local st; st="$(print_state)"
    case "$st" in
        printing|paused)
            die_with_fix "a print is ${st} right now, so I will not change your printer" \
                "wait until the print is finished or cancelled, then run this again. (--check and --dry-run still work.)" ;;
    esac
}

klipper_active() { # 0 = the Klipper service is running
    [ "$TESTING" = 1 ] && return 1
    command -v systemctl >/dev/null 2>&1 || return 1
    systemctl is-active --quiet "$KLIPPER_SERVICE" 2>/dev/null
}

svc_restart() {
    if [ "$(id -u)" = 0 ]; then systemctl restart "$1"; else sudo systemctl restart "$1"; fi
}

check_ace_usb() {
    [ "$TESTING" = 1 ] && [ -z "${ACE_USB_LIST:-}" ] && return 0
    local seen
    seen="$( { ls /dev/serial/by-id 2>/dev/null; lsusb 2>/dev/null; echo "${ACE_USB_LIST:-}"; } | grep -iE 'anycubic|ace|28e9' | head -1 || true)"
    if [ -n "$seen" ]; then
        print_success "ACE USB device found"
    else
        print_warning "I do not see an ACE Pro on USB. Continuing anyway."
        why "it may be unplugged or powered off. The install works without it; the driver connects once the unit is on."
        warn_later "No ACE USB device was seen during the install. Plug in the ACE (data wires only, see docs/HARDWARE.md), power it, then run ./installer.sh --check."
    fi
}

find_dirs() {
    [ -n "$KLIPPER_DIR" ] || KLIPPER_DIR="$INSTALL_HOME/klipper"
    [ -n "$CONFIG_DIR" ]  || CONFIG_DIR="$INSTALL_HOME/printer_data/config"
    [ -d "$KLIPPER_DIR/klippy/extras" ] || die_with_fix "Klipper was not found in $KLIPPER_DIR" \
        "run it with   --klipper-dir /path/to/klipper   (the folder that holds klippy/)."
    [ -f "$CONFIG_DIR/printer.cfg" ] || die_with_fix "there is no printer.cfg in $CONFIG_DIR" \
        "run it with   --config-dir /path/to/printer_data/config"
    print_success "Klipper: $KLIPPER_DIR"
    print_success "Config:  $CONFIG_DIR"
}

# The installer is for WonderMaker's own config. Their tool changes are what everything here builds on.
check_is_wondermaker() {
    local ok=1 m
    [ -f "$CONFIG_DIR/zru-s.cfg" ] || ok=0
    for m in "gcode_macro _CHANGE_TOOL" "gcode_macro UNLOAD_FILAMENT" "filament_switch_sensor path_0"; do
        grep -qiE "^\[${m}\]" "$CONFIG_DIR"/*.cfg 2>/dev/null || ok=0
    done
    if [ "$ok" = 1 ]; then
        print_success "WonderMaker ZR Ultra config found (zru-s.cfg, _CHANGE_TOOL, path_N sensors)"
    else
        die_with_fix "this does not look like a WonderMaker ZR Ultra / Ultra-S config" \
            "run it on the machine that has WonderMaker's printer.cfg, zru-s.cfg and the hub sensors path_0..path_3. For other printers use https://github.com/ducati1198/acepro-any-klipper"
    fi
}

check_driver_source() {
    [ -f "$REPO_DIR/extras/ace/__init__.py" ] || die_with_fix "the ACE driver was not found in $REPO_DIR/extras/ace" \
        "run this script from a full clone:   git clone https://github.com/ducati1198/wm-ultra-fluidd-acepro-panel"
    local py; py="$(klippy_python)"
    if "$py" -m py_compile "$REPO_DIR"/extras/ace/*.py "$REPO_DIR/extras/virtual_pins.py" "$REPO_DIR/extras/temperature_ace.py" 2>/dev/null; then
        print_success "Driver compiles under $("$py" -c 'import sys;print("Python %d.%d"%sys.version_info[:2])')"
    else
        die_with_fix "the ACE driver does not compile under $py" "check the Python version of Klipper's environment (klippy-env); it needs 3.9 or newer."
    fi
    find "$REPO_DIR/extras" -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true
    if ! "$py" -c 'import serial' 2>/dev/null; then
        warn_later "pyserial is missing in Klipper's environment. Install it:  $INSTALL_HOME/klippy-env/bin/pip install pyserial"
    fi
}

# ============================================================================
# Stage the files (nothing is written to the printer until you confirm)
# ============================================================================

keep_value() { # staged_file existing_file prefix key   (prefix = "variable_" or "")
    local sf="$1" ef="$2" pre="$3" k="$4" val
    [ -f "$ef" ] && [ -f "$sf" ] || return 0
    val="$(sed -nE "s/^${pre}${k}:[[:space:]]*([^[:space:]#]+).*/\1/p" "$ef" | head -1)"
    [ -n "$val" ] || return 0
    sed -i -E "s/^(${pre}${k}:[[:space:]]*)[^[:space:]#]+/\1${val}/" "$sf"
}

stage_files() {
    local f k
    STAGE="$(mktemp -d)"
    for f in "${CFG_FILES[@]}"; do cp "$SCRIPT_DIR/config/$f" "$STAGE/$f"; done
    if [ "$UPDATING" = 1 ]; then
        for k in "${KEEP_VARS_ACE[@]}";     do keep_value "$STAGE/wm_ace.cfg" "$CONFIG_DIR/wm_ace.cfg" "variable_" "$k"; done
        for k in "${KEEP_VARS_ENDLESS[@]}"; do keep_value "$STAGE/wm_endless.cfg" "$CONFIG_DIR/wm_endless.cfg" "variable_" "$k"; done
        for k in "${KEEP_OPTS_DRIVER[@]}";  do keep_value "$STAGE/wm_ace_driver.cfg" "$CONFIG_DIR/wm_ace_driver.cfg" "" "$k"; done
    else
        sed -i -E "s/^(variable_auto:[[:space:]]*)[0-9]+/\1${WANT_AUTO}/" "$STAGE/wm_ace.cfg"
    fi
    if [ "$WANT_ENDLESS" = 0 ]; then rm -f "$STAGE/wm_endless.cfg"; fi
    if [ "$HAVE_ACE" = 0 ]; then rm -f "$STAGE/wm_ace.cfg" "$STAGE/wm_ace_driver.cfg"; fi
}

# 0 = this config file is part of the install (staged now, or already in the config folder)
cfg_wanted() { [ -f "${STAGE:-/nonexistent}/$1" ] || [ -f "$CONFIG_DIR/$1" ]; }

include_present() { grep -qE "^\s*\[include\s+$1\]" "$CONFIG_DIR/printer.cfg" 2>/dev/null; }

show_plan() {
    local f
    echo "Config files written to $CONFIG_DIR:"
    for f in "$STAGE"/*; do
        f="$(basename "$f")"
        if [ -e "$CONFIG_DIR/$f" ] && cmp -s "$STAGE/$f" "$CONFIG_DIR/$f"; then echo "  =  $f (unchanged)"
        elif [ -e "$CONFIG_DIR/$f" ]; then echo "  ~  $f (replaced; your tuned values are kept)"
        else echo "  +  $f"; fi
    done
    echo "printer.cfg gets these lines (just above the SAVE_CONFIG block, after [save_variables]; nothing else is edited):"
    for f in "${INCLUDE_LINES[@]}"; do
        cfg_wanted "$(echo "$f" | sed -E 's/\[include ([^]]+)\]/\1/')" || continue
        include_present "$(echo "$f" | sed -E 's/\[include ([^]]+)\]/\1/;s/\./\\./g')" && echo "  =  $f (already there)" || echo "  +  $f"
    done
    if [ "$HAVE_ACE" = 1 ]; then
        echo "Links into $KLIPPER_DIR/klippy/extras:  ace, virtual_pins.py, temperature_ace.py  (to $REPO_DIR/extras)"
    else
        echo "ACE driver: not installed (no ACE Pro). Install again later to add it."
    fi
    [ "$WANT_FLUIDD" = 1 ] && echo "Fluidd:  $FLUIDD_DIR gets the WonderMaker Toolheads + ACE panel (the old folder is saved first)"
    [ "$WANT_FLUIDD" = 0 ] && echo "Fluidd:  not changed"
    echo "Klipper: NOT started or restarted by the install. No board is flashed."
}

# ============================================================================
# Applying
# ============================================================================

apply_stage() {
    local f t
    for f in "$STAGE"/*; do
        f="$(basename "$f")"; t="$CONFIG_DIR/$f"
        if [ -e "$t" ] && cmp -s "$STAGE/$f" "$t"; then continue; fi
        backup_path "$t"
        is_symlink "$t" && rm -f "$t"
        cp "$STAGE/$f" "$t"
        print_success "Wrote $t"
    done
}

add_before_save_config() { # file text
    local f="$1" text="$2" tmp
    tmp="$(mktemp)"
    awk -v text="$text" '
        /^#\*# <-+ SAVE_CONFIG -+>/ && !d { print text; print ""; d=1 }
        { print }
        END { if (!d) print text }' "$f" > "$tmp" && cat "$tmp" > "$f"
    rm -f "$tmp"
}

ensure_includes() {
    # Klipper loads sections in file order and the ACE driver reads [save_variables] while it loads,
    # so our lines must come AFTER that section: they go in one block just above SAVE_CONFIG.
    local pc="$CONFIG_DIR/printer.cfg" tmp l block="" want=0
    for l in "${INCLUDE_LINES[@]}"; do
        cfg_wanted "$(echo "$l" | sed -E 's/\[include ([^]]+)\]/\1/')" || continue
        block+="${block:+$'\n'}$l"; want=1
    done
    [ "$want" = 1 ] || return 0
    tmp="$(mktemp)"
    cp "$pc" "$tmp"
    for l in "${INCLUDE_LINES[@]}"; do
        sed -i -E "/^[[:space:]]*\[include[[:space:]]+$(echo "$l" | sed -E 's/\[include ([^]]+)\]/\1/;s/\./\\./g')\]/d" "$tmp"
    done
    local t2; t2="$(mktemp)"
    awk -v text="$block" '/^#\*# <-+ SAVE_CONFIG -+>/ && !d { print text; d=1 } { print } END { if (!d) print text }' "$tmp" > "$t2" && cat "$t2" > "$tmp"; rm -f "$t2"
    if cmp -s "$tmp" "$pc"; then rm -f "$tmp"; return 0; fi
    backup_path "$pc"
    cat "$tmp" > "$pc"; rm -f "$tmp"
    print_success "printer.cfg: the ACE include lines are now above SAVE_CONFIG, after [save_variables]"
}

link_item() { # source target label
    local src="$1" dst="$2" label="$3" old
    [ -e "$src" ] || { print_warning "$label: $src is missing, skipped"; return 1; }
    if is_symlink "$dst" && [ "$(readlink "$dst")" = "$src" ]; then print_success "$label already linked"; return 0; fi
    if [ -e "$dst" ] && ! is_symlink "$dst"; then
        if [ "$label" = "virtual_pins" ] && grep -q "virtual_pin" "$dst" 2>/dev/null; then
            print_success "Klipper already has its own virtual_pins.py, keeping it"; return 0
        fi
        warn_later "$dst already exists and is not a link, so I left it alone ($label)."; return 1
    fi
    if is_symlink "$dst"; then old="$(readlink "$dst")"; echo "LINK $dst $old" >> "$BACKUP_DIR/manifest.txt"; rm -f "$dst"
    else echo "LINK $dst -" >> "$BACKUP_DIR/manifest.txt"; fi
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst" && print_success "Linked $label"
}

link_driver() {
    local x="$KLIPPER_DIR/klippy/extras"
    link_item "$REPO_DIR/extras/ace" "$x/ace" "ACE driver"
    link_item "$REPO_DIR/extras/virtual_pins.py" "$x/virtual_pins.py" "virtual_pins"
    link_item "$REPO_DIR/extras/temperature_ace.py" "$x/temperature_ace.py" "ACE temperature sensor"
}

# The original Fluidd is saved once, for good, in $BACKUP_ROOT/original-fluidd. Nothing in this installer deletes it
# (the pruning only touches fluidd_backup_* and wm-* folders), so --uninstall can always put it back.
ORIGINAL_FLUIDD() { echo "$BACKUP_ROOT/original-fluidd"; }
has_panel() { grep -rlq "ACE feeder" "$1/assets" 2>/dev/null; }
save_original_fluidd() { # fluidd_dir
    local fd="$1" orig src="" b; orig="$(ORIGINAL_FLUIDD)"
    [ -d "$orig" ] && return 0
    if ! has_panel "$fd"; then src="$fd"
    else # already our panel (installed by an older version): the oldest saved copy that is still the stock Fluidd
        for b in $(ls -1d "${fd}"_backup_* 2>/dev/null | sort); do has_panel "$b" || { src="$b"; break; }; done
    fi
    if [ -z "$src" ]; then print_info "No untouched copy of the original Fluidd was found, so it could not be saved for good."; return 0; fi
    mkdir -p "$BACKUP_ROOT" && cp -a "$src" "$orig" && echo "saved $(date) from $src" > "$BACKUP_ROOT/original-fluidd.info" \
        && print_success "Original Fluidd saved for good → $orig (the installer never deletes it)"
}

install_fluidd_panel() {
    local fluidd_dir="$1" zip="$SCRIPT_DIR/fluidd/fluidd-v1.37.7-zr-ace.zip" backup
    [ -f "$zip" ] || { warn_later "Fluidd build not found: $zip"; return 1; }
    if [ -f "$zip.sha256" ] && ! (cd "$SCRIPT_DIR/fluidd" && sha256sum -c "$(basename "$zip.sha256")" >/dev/null 2>&1); then
        warn_later "Checksum of the Fluidd build does not match. The panel was not installed."; return 1
    fi
    [ -d "$fluidd_dir" ] || { warn_later "Fluidd folder not found: $fluidd_dir"; return 1; }
    save_original_fluidd "$fluidd_dir"
    backup="${fluidd_dir}_backup_$(timestamp)"
    cp -a "$fluidd_dir" "$backup" && echo "FLUIDD $fluidd_dir $backup" >> "$BACKUP_DIR/manifest.txt"
    print_success "Backed up Fluidd → $backup"
    prune_backups "$fluidd_dir"
    rm -rf "$fluidd_dir/assets"
    if command -v unzip >/dev/null 2>&1; then unzip -qo "$zip" -x config.json -d "$fluidd_dir"
    else python3 -I - "$zip" "$fluidd_dir" <<'PYZIP'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
for n in z.namelist():
    if n != "config.json":
        z.extract(n, sys.argv[2])
PYZIP
    fi
    [ -f "$fluidd_dir/config.json" ] || python3 -I -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extract('config.json', sys.argv[2])" "$zip" "$fluidd_dir"
    chmod -R a+rX "$fluidd_dir" 2>/dev/null || true
    if grep -rlq "ACE feeder" "$fluidd_dir/assets" 2>/dev/null; then
        print_success "Fluidd Toolheads + ACE panel installed (hard-refresh the browser to load it)"
    else
        print_error "The panel was not found after unpacking. Restoring Fluidd."
        rm -rf "$fluidd_dir" && cp -a "$backup" "$fluidd_dir"; return 1
    fi
    if grep -qE '^\[update_manager[[:space:]]+fluidd\]' "$CONFIG_DIR/moonraker.conf" 2>/dev/null; then
        warn_later "moonraker.conf has [update_manager fluidd]: updating Fluidd there replaces this build. Run ./installer.sh --update --fluidd after a Fluidd update."
    fi
}

save_answers() {
    local f; f="$(CONF_FILE)"
    backup_path "$f"
    {
        echo "VERSION=\"$VERSION\""
        echo "ACE=\"$HAVE_ACE\""
        echo "AUTO=\"$WANT_AUTO\""
        echo "ENDLESS=\"$WANT_ENDLESS\""
        echo "FLUIDD=\"$WANT_FLUIDD\""
        echo "REPO=\"$REPO_DIR\""
    } > "$f"
}

restart_question() {
    echo
    if klipper_active; then
        print_info "Klipper is running. It must restart once to load the ACE driver."
        why "the ACE is not used until Klipper has restarted. Do not restart in the middle of a print."
        if ask_yn "Restart Klipper now?" N; then
            svc_restart "$KLIPPER_SERVICE" && print_success "Klipper restarted. Read ~/printer_data/logs/klippy.log for '[ace]' lines."
        else
            print_info "Not restarted. Do it from Fluidd (FIRMWARE_RESTART) or:  sudo systemctl restart $KLIPPER_SERVICE"
        fi
    else
        print_info "Klipper is not running, so nothing was restarted. The ACE driver loads the next time Klipper starts."
    fi
}

final_steps() {
    local w
    print_header "Done"
    print_success "WonderMaker Ultra panel$([ "$HAVE_ACE" = 1 ] && echo " + ACE Pro") installed (v$VERSION)."
    if [ "${#WARNINGS[@]}" -gt 0 ]; then
        echo; print_warning "Things to look at:"
        for w in "${WARNINGS[@]}"; do echo "  - $w"; done
    fi
    echo
    echo "Next:"
    echo "  1. Restart Klipper once (if you installed config files), then run  ./installer.sh --check"
    if [ "$HAVE_ACE" = 1 ]; then
        echo "  2. Fluidd: hard-refresh the browser (Ctrl/Cmd+Shift+R). The Toolheads card shows the ACE parts once Klipper reports the ACE."
        echo "  3. First tests are in the README, section 6 (dryer, manual feed, then ACE_WM_LOAD T=0). Stay at the printer."
    else
        echo "  2. Fluidd: hard-refresh the browser (Ctrl/Cmd+Shift+R). The Toolheads card works without an ACE; the ACE parts stay hidden."
        echo "  3. Got an ACE Pro later? Run ./installer.sh again and answer yes to the ACE question."
    fi
    echo "Undo everything:  ./installer.sh --undo"
}

# ============================================================================
# Install / update
# ============================================================================

# ============================================================================
# The factory screen board only: wrong clock and archived apt (other machines do not need this)
# ============================================================================

on_factory_board() { # 0 = this is the original WonderMaker screen board (Debian 11 with the factory app makerbase-client)
    [ "$TESTING" = 1 ] && { [ "${ACE_TEST_FACTORY_BOARD:-0}" = 1 ]; return; }
    grep -q 'VERSION_ID="11"' /etc/os-release 2>/dev/null && systemctl cat makerbase-client.service >/dev/null 2>&1
}
sudo_run() { if [ "$TESTING" = 1 ]; then echo "[test] sudo $*" >> "$INSTALL_HOME/.sudo.log"; return 0; fi; if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi; }

fix_factory_board() { # clock (NTP) + apt, asked once. Does nothing on a Raspberry Pi or any other machine.
    on_factory_board || return 0
    print_header "This is the factory screen board: date, time and apt"
    progress_bar 0 3 "Step 1 of 3: date and time"
    local synced now
    if [ "$TESTING" = 1 ]; then synced="${ACE_TEST_NTP_SYNCED:-no}"; else synced="$(timedatectl show -p NTPSynchronized --value 2>/dev/null)"; fi
    now="$(date '+%Y-%m-%d %H:%M %Z')"
    if [ "$synced" = yes ]; then print_success "The clock is set automatically (NTP): $now"
    else
        echo "  The board's clock is not synchronised automatically. Now: $now"
        why "A wrong date makes HTTPS downloads and apt fail. Automatic time sync keeps it right whenever the board is online."
        if [ "$DRY" = 1 ]; then echo -e "  ${DIM}would run: sudo timedatectl set-ntp true${NC}"
        elif [ -f "$INSTALL_HOME/.wm-ntp-asked" ] && [ $(( $(date +%s) - $(cat "$INSTALL_HOME/.wm-ntp-asked" 2>/dev/null || echo 0) )) -lt 3600 ]; then print_info "Automatic time sync was turned on a few minutes ago; the clock can take a little while to catch up. Not asking again."
        elif ask_yn "Turn on automatic time sync (NTP)?" Y; then
            date +%s > "$INSTALL_HOME/.wm-ntp-asked"
            sudo_run timedatectl set-ntp true || sudo_run systemctl enable --now systemd-timesyncd || true
            if [ "$TESTING" != 1 ]; then
                local i; for i in $(seq 1 15); do [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = yes ] && break; sleep 2; done
                if [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" != yes ]; then   # no time server reachable: take the time once from a web server's Date header
                    local d; d="$(curl -sI -m 8 http://github.com 2>/dev/null | sed -n 's/^[Dd]ate: *//p' | tr -d '\r' | head -1)"
                    [ -n "$d" ] && sudo date -u -s "$d" >/dev/null 2>&1 && print_info "No time server answered; the clock was set once from GitHub's reply."
                fi
            fi
            print_success "Automatic time sync is on: $(date '+%Y-%m-%d %H:%M %Z')"
        else print_info "Left as it is."; fi
    fi
    # apt: Debian 11 is archived. Same fix as README 3.2a; apt upgrade is never run.
    local sl=/etc/apt/sources.list conf=/etc/apt/apt.conf.d/99no-check-valid-until
    progress_bar 1 3 "Step 2 of 3: apt sources"
    if grep -qE '^deb .*(mirrors|deb\.debian|security\.debian|ftp\.)' "$sl" 2>/dev/null && [ "$TESTING" != 1 ]; then
        if [ "$DRY" = 1 ]; then echo -e "  ${DIM}would point apt at archive.debian.org (a copy of sources.list is kept)${NC}"
        elif ask_yn "Point apt at the Debian archive (a copy of $sl is kept as $sl.orig)?" Y; then
            [ -f "$sl.orig" ] || sudo_run cp "$sl" "$sl.orig"
            sudo_run sed -i -E 's#https?://[^ /]+/debian-security#http://archive.debian.org/debian-security#; t; s#https?://[^ /]+/debian/?#http://archive.debian.org/debian/#' "$sl"
            print_success "apt now uses archive.debian.org"
        fi
    fi
    progress_bar 2 3 "Step 3 of 3: apt date check"
    if [ ! -f "$conf" ]; then
        if [ "$DRY" = 1 ]; then echo -e "  ${DIM}would write $conf (apt ignores the old package-list dates)${NC}"
        else printf 'Acquire::Check-Valid-Until "false";\nAcquire::Check-Date "false";\n' | sudo_run tee "$conf" >/dev/null; [ "$TESTING" = 1 ] && echo "[test] write $conf" >> "$INSTALL_HOME/.sudo.log"; print_success "apt ignores the old package-list dates"; fi
    else print_success "apt already ignores the old package-list dates"; fi
    progress_bar 3 3 "Done"
    print_info "Never run apt upgrade on this board: it can replace WonderMaker's held X server."
}


do_install() {
    local existing=0
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   WonderMaker Ultra panel + ACE  ·  installer  v${VERSION}$(printf '%*s' $((9 - ${#VERSION})) '')║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
    echo "Nothing is changed until you confirm the summary. No board is ever flashed."
    echo "Press ENTER to accept the [default]."
    [ "$DRY" = 1 ] && print_info "DRY RUN: I will show what would change and change nothing."

    print_header "1 of 4 · Looking at your printer"
    [ "$DRY" = 1 ] || guard_not_printing
    find_dirs
    check_is_wondermaker
    fix_factory_board
    check_disk_space
    { [ -f "$CONFIG_DIR/wm_ace.cfg" ] || [ -f "$(CONF_FILE)" ]; } && existing=1

    if [ "$MODE" = "update" ] && [ "$existing" = 0 ]; then
        die_with_fix "there is no ACE install to update in $CONFIG_DIR" "run   ./installer.sh   to install first."
    fi
    if [ "$existing" = 1 ]; then
        if [ "$MODE" = "update" ] || ask_yn "An install was found. Update it and keep your tuned values?" Y "no starts a fresh install; your current files are saved first."; then
            UPDATING=1
            OLD_VERSION="$(kv_get "$(CONF_FILE)" VERSION || true)"
            HAVE_ACE="$(kv_get "$(CONF_FILE)" ACE || echo 1)"; HAVE_ACE="${HAVE_ACE:-1}"
            WANT_AUTO="$(kv_get "$(CONF_FILE)" AUTO || echo 1)"; WANT_AUTO="${WANT_AUTO:-1}"
            WANT_ENDLESS="$(kv_get "$(CONF_FILE)" ENDLESS || echo 1)"; WANT_ENDLESS="${WANT_ENDLESS:-1}"
            [ -f "$CONFIG_DIR/wm_endless.cfg" ] || WANT_ENDLESS=0
        fi
    fi

    print_header "2 of 4 · Questions"
    local fl="$INSTALL_HOME/fluidd"
    if [ "$UPDATING" = 0 ]; then
        ask_yn "Do you have an Anycubic ACE Pro to connect?" Y \
            "no is fine: you then get the WonderMaker Toolheads panel (and the endless-spool option) without any ACE parts. You can run the installer again later." && HAVE_ACE=1 || HAVE_ACE=0
    fi
    if [ "$HAVE_ACE" = 1 ]; then
        check_driver_source
        [ "$DRY" = 1 ] || check_ace_usb
    fi
    if [ "$UPDATING" = 0 ]; then
        if [ "$HAVE_ACE" = 1 ]; then
            ask_yn "Load a spool automatically when you put it into an ACE slot?" Y \
                "the ACE feeds it to the hub and the toolhead sensor. You can switch this later with ACE_WM_AUTO ENABLE=0." && WANT_AUTO=1 || WANT_AUTO=0
        fi
        ask_yn "Add the experimental endless-spool macros (switched OFF until you turn them on in Fluidd)?" Y \
            "when a toolhead runs out, the Toolheads card offers to continue on a spare head with the same colour and material." && WANT_ENDLESS=1 || WANT_ENDLESS=0
    fi
    if [ -d "$fl" ]; then
        local q="Install the WonderMaker Toolheads panel$([ "$HAVE_ACE" = 1 ] && echo " (with the ACE parts)") into Fluidd?"
        [ "$UPDATING" = 1 ] && q="Also refresh the Fluidd panel?"
        ask_yn "$q" "$([ "$UPDATING" = 1 ] && echo N || echo Y)" "your Fluidd folder is saved first and can be put back with --undo." && { WANT_FLUIDD=1; FLUIDD_DIR="$fl"; }
    else
        print_info "No Fluidd folder at $fl, so the panel is skipped."
    fi

    if [ "$HAVE_ACE" = 0 ] && [ "$WANT_ENDLESS" = 0 ] && [ "$WANT_FLUIDD" = 0 ]; then
        die_with_fix "nothing is selected (no ACE, no endless spool, no Fluidd panel)" "run it again and say yes to at least one of them."
    fi

    print_header "3 of 4 · What will change"
    stage_files
    echo "Backup of everything that changes:  $BACKUP_ROOT/wm-<date>   (undo: ./installer.sh --undo)"
    echo
    show_plan
    echo
    if [ "$DRY" = 1 ]; then
        echo; print_success "Dry run finished. Nothing was changed."
        return 0
    fi
    ask_yn "Continue?" Y || { print_info "Cancelled. Nothing was changed."; return 0; }

    print_header "4 of 4 · Installing"
    BACKUP_DIR="$BACKUP_ROOT/wm-$(timestamp)"
    mkdir -p "$BACKUP_DIR" && : > "$BACKUP_DIR/manifest.txt"
    echo "$VERSION" > "$BACKUP_DIR/installer-version.txt"
    print_success "Backup folder: $BACKUP_DIR"
    prune_backups

    local pt=5; progress_bar 0 $pt "Step 1 of $pt: driver links"
    [ "$HAVE_ACE" = 1 ] && link_driver
    progress_bar 1 $pt "Step 2 of $pt: config files"
    apply_stage
    progress_bar 2 $pt "Step 3 of $pt: include lines in printer.cfg"
    ensure_includes
    progress_bar 3 $pt "Step 4 of $pt: Fluidd panel"
    [ "$WANT_FLUIDD" = 1 ] && install_fluidd_panel "$FLUIDD_DIR"
    progress_bar 4 $pt "Step 5 of $pt: saving your answers"
    save_answers
    progress_bar 5 $pt "Done"
    find "$REPO_DIR/extras" -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true

    [ "$UPDATING" = 1 ] && [ -n "$OLD_VERSION" ] && [ "$OLD_VERSION" != "$VERSION" ] && print_info "Updated from v$OLD_VERSION to v$VERSION."
    restart_question
    final_steps
}

# ============================================================================
# Uninstall / undo / check / repair
# ============================================================================

remove_include_lines() {
    local pc="$CONFIG_DIR/printer.cfg" l
    [ -f "$pc" ] || return 0
    backup_path "$pc"
    for l in wm_ace_driver.cfg wm_ace.cfg wm_endless.cfg wm_stats.cfg; do
        sed -i -E "/^[[:space:]]*\[include[[:space:]]+${l//./\\.}\]/d" "$pc"
    done
    print_success "Removed the ACE include lines from printer.cfg"
}

remove_link() { # path label  (only our own links)
    local p="$1" label="$2"
    if is_symlink "$p" && [[ "$(readlink "$p")" == "$REPO_DIR"/extras/* ]]; then
        echo "LINK $p $(readlink "$p")" >> "$BACKUP_DIR/manifest.txt"
        rm -f "$p" && print_success "Removed link $label"
    fi
}

do_uninstall() {
    local f x
    guard_not_printing
    find_dirs
    x="$KLIPPER_DIR/klippy/extras"
    print_header "Uninstall ACE Pro (WonderMaker Ultra)"
    echo "This removes what the installer added:"
    for f in "${CFG_FILES[@]}" "$CONF_NAME"; do [ -e "$CONFIG_DIR/$f" ] && echo "  FILE   $CONFIG_DIR/$f"; done
    for f in ace temperature_ace.py virtual_pins.py; do is_symlink "$x/$f" && echo "  LINK   $x/$f"; done
    grep -qE '^\s*\[include\s+wm_(ace_driver|ace|endless|stats)\.cfg\]' "$CONFIG_DIR/printer.cfg" 2>/dev/null && echo "  EDIT   printer.cfg (our include lines)"
    local fl="$INSTALL_HOME/fluidd" restore_fl=0
    if has_panel "$fl" && [ -d "$(ORIGINAL_FLUIDD)" ]; then restore_fl=1; echo "  FLUIDD $fl (the original Fluidd comes back, your config.json is kept)"; fi
    echo
    print_info "Left alone: every WonderMaker file, Python packages."
    [ "$restore_fl" = 0 ] && print_info "The Fluidd panel stays (no saved original Fluidd to put back)."
    why "everything is saved first. ./installer.sh --undo puts it all back."
    [ "$DRY" = 1 ] && { print_info "Dry run: nothing removed."; return 0; }
    ask_yn "Remove the ACE Pro install?" N || { print_info "Cancelled. Nothing changed."; return 0; }
    if [ "$restore_fl" = 1 ]; then ask_yn "Also put the original Fluidd back?" Y "the panel in Fluidd is saved first; --undo brings it back." || restore_fl=0; fi

    BACKUP_DIR="$BACKUP_ROOT/wm-$(timestamp)-uninstall"
    mkdir -p "$BACKUP_DIR" && : > "$BACKUP_DIR/manifest.txt"
    progress_bar 0 3 "Step 1 of 3: include lines in printer.cfg"
    remove_include_lines
    progress_bar 1 3 "Step 2 of 3: config files"
    for f in "${CFG_FILES[@]}" "$CONF_NAME"; do
        if [ -e "$CONFIG_DIR/$f" ]; then backup_path "$CONFIG_DIR/$f"; rm -f "$CONFIG_DIR/$f"; print_success "Removed $f"; fi
    done
    progress_bar 2 3 "Step 3 of 3: driver links"
    for f in ace temperature_ace.py virtual_pins.py; do remove_link "$x/$f" "$f"; done
    if [ "$restore_fl" = 1 ]; then
        progress_bar 3 4 "Step 4 of 4: original Fluidd"
        local fb="${fl}_backup_$(timestamp)-uninstall" cj="$BACKUP_DIR/config.json.keep"
        cp -a "$fl" "$fb" && echo "FLUIDD $fl $fb" >> "$BACKUP_DIR/manifest.txt"
        [ -f "$fl/config.json" ] && cp -a "$fl/config.json" "$cj"
        rm -rf "$fl" && cp -a "$(ORIGINAL_FLUIDD)" "$fl" && { [ -f "$cj" ] && cp -a "$cj" "$fl/config.json"; rm -f "$cj"; } \
            && print_success "Original Fluidd put back (your config.json kept)" || print_error "Could not put the original Fluidd back. Your panel is saved in $fb"
        prune_backups "$fl"
    fi
    progress_bar 3 3 "Done"
    echo
    print_success "ACE Pro is uninstalled. Saved in: $BACKUP_DIR"
    print_info "Restart Klipper when you next use the printer. To bring it all back: ./installer.sh --undo"
}

do_undo() {
    local dir="${1:-}" line kind a b
    [ "$DRY" = 1 ] || guard_not_printing
    [ -n "$dir" ] || dir="$(ls -d "$BACKUP_ROOT"/wm-*/ 2>/dev/null | sed 's#/$##' | sort | tail -1)"
    dir="${dir%/}"
    [ -n "$dir" ] && [ -f "$dir/manifest.txt" ] || die_with_fix "there is no backup to restore in $BACKUP_ROOT" "backups are made by this installer before it changes anything"
    echo "Restoring from: $dir"
    sed 's/^/  /' "$dir/manifest.txt"
    [ "$DRY" = 1 ] && { print_info "Dry run: nothing restored."; return 0; }
    ask_yn "Put these files back?" Y || { print_info "Cancelled."; return 0; }
    local un ui=0; un="$(wc -l < "$dir/manifest.txt" | tr -d ' ')"
    while IFS= read -r line; do
        progress_bar "$ui" "$un" "Putting files back (step $((ui+1)) of $un)"; ui=$((ui+1))
        kind="${line%% *}"; a="${line#* }"
        case "$kind" in
            MOD)  mkdir -p "$(dirname "$a")"; rm -rf "$a"; cp -a "$dir/files$a" "$a" && print_success "Restored $a" ;;
            NEW)  rm -rf "$a" && print_success "Removed $a (it was new)" ;;
            LINK) b="${a#* }"; a="${a%% *}"; rm -f "$a"; [ "$b" != "-" ] && ln -s "$b" "$a"; print_success "Link $a put back" ;;
            FLUIDD) b="${a#* }"; a="${a%% *}"; if [ -d "$b" ]; then rm -rf "$a" && cp -a "$b" "$a" && print_success "Fluidd restored from $b"; fi ;;
        esac
    done < <(tac "$dir/manifest.txt")
    progress_bar "$un" "$un" "Done"
    print_success "Done. Restart Klipper when you next use the printer."
}

do_check() {
    local bad=0 f x state py have
    find_dirs
    echo -e "${BLUE}WonderMaker Ultra panel / ACE Pro check${NC}   installer v$VERSION"
    progress_bar 0 4 "Check 1 of 4: installed version and config files"
    have="$(kv_get "$(CONF_FILE)" ACE || echo 1)"; have="${have:-1}"
    local inst; inst="$(kv_get "$(CONF_FILE)" VERSION || true)"
    [ -n "$inst" ] && [ "$inst" != "$VERSION" ] && print_warning "Installed with v$inst, this download is v$VERSION. Run ./installer.sh --update."
    check_is_wondermaker
    if [ "$have" = 1 ]; then
        for f in wm_ace_driver.cfg wm_ace.cfg; do
            [ -f "$CONFIG_DIR/$f" ] && print_success "$f present" || { print_error "$f is missing"; bad=1; }
            include_present "${f//./\\.}" && print_success "printer.cfg includes $f" || { print_error "printer.cfg does not include $f"; bad=1; }
        done
    else
        print_info "Installed without an ACE Pro (panel only). ACE checks skipped."
    fi
    if [ -f "$CONFIG_DIR/wm_endless.cfg" ]; then
        print_success "wm_endless.cfg present (experimental)"
        include_present "wm_endless\\.cfg" && print_success "printer.cfg includes wm_endless.cfg" || { print_error "printer.cfg does not include wm_endless.cfg"; bad=1; }
    else
        print_info "wm_endless.cfg not installed (endless spool offer stays hidden)"
    fi
    if [ -f "$CONFIG_DIR/wm_stats.cfg" ]; then
        print_success "wm_stats.cfg present (counters, tool map)"
        include_present "wm_stats\\.cfg" && print_success "printer.cfg includes wm_stats.cfg" || { print_error "printer.cfg does not include wm_stats.cfg"; bad=1; }
    else
        print_info "wm_stats.cfg not installed yet (run ./installer.sh --update)"
    fi
    x="$KLIPPER_DIR/klippy/extras"
    progress_bar 1 4 "Check 2 of 4: ACE driver"
    if [ "$have" = 1 ]; then
        grep -qE '^register_tool_commands:[[:space:]]*False' "$CONFIG_DIR/wm_ace_driver.cfg" 2>/dev/null \
            && print_success "driver will not create T0..T7 (WonderMaker owns them)" \
            || { print_error "register_tool_commands: False is missing in wm_ace_driver.cfg: the driver would replace WonderMaker's T0..T3"; bad=1; }
        for f in ace temperature_ace.py virtual_pins.py; do
            if [ -e "$x/$f" ]; then print_success "$f in Klipper's extras folder"
            elif is_symlink "$x/$f"; then print_error "$x/$f is a broken link (was the repository moved?)"; bad=1
            else print_error "$x/$f is missing"; bad=1; fi
        done
        grep -q "register_tool_commands" "$x/ace/config.py" 2>/dev/null \
            && print_success "driver has the register_tool_commands option" \
            || { print_error "the linked driver is too old (no register_tool_commands). Use extras/ace from this repository."; bad=1; }
        py="$(klippy_python)"
        "$py" -m py_compile "$x"/ace/*.py 2>/dev/null && print_success "driver compiles" || { print_error "driver does not compile"; bad=1; }
        find "$REPO_DIR/extras" -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true
    fi
    progress_bar 2 4 "Check 3 of 4: Fluidd panel"
    if [ -d "$INSTALL_HOME/fluidd/assets" ]; then
        grep -rlq "ACE feeder" "$INSTALL_HOME/fluidd/assets" 2>/dev/null && print_success "Fluidd has the Toolheads panel" || print_info "Fluidd is not the panel build"
    fi
    if command -v curl >/dev/null 2>&1 && [ "$TESTING" = 0 ]; then
        state="$(curl -s -m 3 "$MOONRAKER_URL/printer/info" 2>/dev/null | python3 -I -c 'import sys,json; print(json.load(sys.stdin)["result"]["state"])' 2>/dev/null || true)"
        echo; [ -n "$state" ] && print_info "Klipper state: $state" || print_info "Moonraker is not answering on $MOONRAKER_URL (Klipper may be stopped)"
    fi
    progress_bar 4 4 "Check 4 of 4 done"
    echo; [ "$bad" = 0 ] && print_success "No problems found." || print_error "Problems found (see above). ./installer.sh --repair fixes links and include lines."
    return $bad
}

do_repair() {
    guard_not_printing
    find_dirs
    check_is_wondermaker
    BACKUP_DIR="$BACKUP_ROOT/wm-$(timestamp)-repair"
    mkdir -p "$BACKUP_DIR" && : > "$BACKUP_DIR/manifest.txt"
    [ -f "$CONFIG_DIR/wm_endless.cfg" ] || WANT_ENDLESS=0
    HAVE_ACE="$(kv_get "$(CONF_FILE)" ACE || echo 1)"; HAVE_ACE="${HAVE_ACE:-1}"
    progress_bar 0 2 "Step 1 of 2: driver links"
    [ "$HAVE_ACE" = 1 ] && link_driver
    progress_bar 1 2 "Step 2 of 2: include lines"
    ensure_includes
    progress_bar 2 2 "Done"
    print_success "Repair finished. Run ./installer.sh --check"
}

# ============================================================================
# Doctor and support bundle
# ============================================================================
scrub() {  # remove secrets and private addresses from a stream
    sed -E 's/((password|passwd|token|api_?key|secret|ssid|psk|key)[[:space:]]*[:=][[:space:]]*).*/\1<removed>/I;
            s/\b(10\.[0-9]+\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+)\b/<private-ip>/g;
            s/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/<mac>/g'
}
doc_ok()  { echo -e "  ${GREEN}[ok]${NC}      $1"; }
doc_bad() { echo -e "  ${RED}[problem]${NC} $1"; echo -e "            ${DIM}$2${NC}"; DOC_PROBLEMS=$((DOC_PROBLEMS+1)); }
offer_fix() {  # description, command...
    local d="$1"; shift
    if ask_yn "  Fix: $d?" Y; then "$@" && print_success "done" || print_warning "the fix did not work"; fi
}
doc_relink() {   # restore driver links and include lines (same as --repair, saved first)
    BACKUP_DIR="$BACKUP_ROOT/wm-$(timestamp)-doctor"
    mkdir -p "$BACKUP_DIR" && : > "$BACKUP_DIR/manifest.txt"
    [ -f "$CONFIG_DIR/wm_endless.cfg" ] || WANT_ENDLESS=0
    local f
    if [ "$HAVE_ACE" = 1 ]; then   # put back a missing file only; a file that is there (maybe tuned) is never overwritten
        for f in wm_ace_driver.cfg wm_ace.cfg; do
            [ -f "$CONFIG_DIR/$f" ] || { cp "$SCRIPT_DIR/config/$f" "$CONFIG_DIR/$f" && echo "NEW $CONFIG_DIR/$f" >> "$BACKUP_DIR/manifest.txt" && print_success "Restored $f"; }
        done
    fi
    [ "$HAVE_ACE" = 1 ] && link_driver
    ensure_includes
}
do_doctor() {
    DOC_PROBLEMS=0
    print_header "Doctor (asks before changing anything)"
    progress_bar 0 5 "Doctor 1 of 5: config folder and disk space"
    find_dirs
    HAVE_ACE="$(kv_get "$(CONF_FILE)" ACE || echo 1)"; HAVE_ACE="${HAVE_ACE:-1}"
    local x f broken=0 free inst
    [ -f "$CONFIG_DIR/printer.cfg" ] && doc_ok "printer.cfg found" || doc_bad "printer.cfg not found in $CONFIG_DIR" "run the installer on the machine that runs Klipper, or pass --config-dir"
    free="$(disk_free_mb)"
    [ "${free:-0}" -gt 300 ] && doc_ok "disk space ${free} MB free" || { doc_bad "only ${free} MB free" "Klipper and Fluidd need room to write logs and files."; offer_fix "look for files to erase" do_free_space; }
    progress_bar 1 5 "Doctor 2 of 5: installed version"
    inst="$(kv_get "$(CONF_FILE)" VERSION || true)"
    if [ -z "$inst" ]; then doc_bad "the ACE / panel install is not recorded here" "run ./installer.sh to install."
    elif [ "$inst" != "$VERSION" ]; then doc_bad "installed v$inst, this download is v$VERSION" "update: ./installer.sh --update"
    else doc_ok "installed version matches this download (v$VERSION)"; fi
    x="$KLIPPER_DIR/klippy/extras"
    progress_bar 2 5 "Doctor 3 of 5: driver links and config files"
    if [ "$HAVE_ACE" = 1 ] && [ -n "$inst" ]; then
        for f in wm_ace_driver.cfg wm_ace.cfg; do
            [ -f "$CONFIG_DIR/$f" ] && include_present "${f//./\\.}" || broken=1
        done
        for f in ace temperature_ace.py virtual_pins.py; do [ -e "$x/$f" ] || broken=1; done
        if [ "$broken" = 1 ]; then doc_bad "driver links, config files or include lines are missing" "this is what --repair restores"; offer_fix "restore the links and include lines (saved first)" doc_relink
        else doc_ok "driver links, config files and include lines are in place"; fi
        grep -qE '^register_tool_commands:[[:space:]]*False' "$CONFIG_DIR/wm_ace_driver.cfg" 2>/dev/null && doc_ok "driver will not replace WonderMaker's T0..T3" || doc_bad "register_tool_commands: False is missing in wm_ace_driver.cfg" "the driver would replace WonderMaker's T0..T3; re-run ./installer.sh --update"
    fi
    progress_bar 3 5 "Doctor 4 of 5: Fluidd panel"
    [ -d "$INSTALL_HOME/fluidd/assets" ] && { grep -rlq "ACE feeder" "$INSTALL_HOME/fluidd/assets" 2>/dev/null && doc_ok "Fluidd has the Toolheads panel" || print_info "Fluidd is not the panel build (./installer.sh --update, and say yes to the panel)"; }
    grep -qE '^\[update_manager[[:space:]]+fluidd\]' "$CONFIG_DIR/moonraker.conf" 2>/dev/null && print_info "moonraker.conf has [update_manager fluidd]: updating Fluidd there replaces this panel build."
    progress_bar 4 5 "Doctor 5 of 5: Klipper and Moonraker"
    if [ "$TESTING" = 0 ] && command -v curl >/dev/null 2>&1; then
        local st; st="$(curl -s -m 3 "$MOONRAKER_URL/printer/info" 2>/dev/null | python3 -I -c 'import sys,json; print(json.load(sys.stdin)["result"]["state"])' 2>/dev/null || true)"
        [ -n "$st" ] && doc_ok "Klipper state: $st" || print_info "Moonraker is not answering on $MOONRAKER_URL (Klipper may be stopped)"
    fi
    progress_bar 5 5 "Doctor finished"
    echo; [ "$DOC_PROBLEMS" = 0 ] && print_success "No problems found." || { print_warning "$DOC_PROBLEMS problem(s) found. For a report to share: ./installer.sh --support-bundle"; return 1; }
}
do_support_bundle() {
    print_header "Support bundle"
    find_dirs
    progress_bar 0 4 "Bundle 1 of 4: system report"
    local w out b f lf; w="$(mktemp -d)"; out="$INSTALL_HOME/ace-support-$(timestamp).tgz"; b="$w/ace-support"; mkdir -p "$b/config" "$b/logs"
    {
        echo "wm-ultra-fluidd-acepro-panel installer $VERSION   date: $(date -u +%FT%TZ)"
        uname -a; [ -r /etc/os-release ] && grep PRETTY /etc/os-release
        echo "python3: $(python3 --version 2>&1)"; df -h "$INSTALL_HOME" | tail -1; free -m 2>/dev/null | sed -n 2p
        echo "--- services"; local s; for s in klipper moonraker nginx; do printf '%-10s active=%s\n' $s "$(systemctl is-active $s 2>/dev/null || echo unknown)"; done
        echo "--- usb"; lsusb 2>/dev/null
        echo "--- usb tree (hubs and what hangs on them)"; lsusb -t 2>/dev/null
        echo "--- serial ports in /dev (an ACE Pro should show as ttyACM*)"; ls -l /dev/ttyACM* /dev/ttyUSB* /dev/serial/by-id/* 2>&1 | head -20
        echo "--- serial ports the ACE driver sees (name, description, hwid)"
        "$(klippy_python)" -m serial.tools.list_ports -v 2>&1 | head -40
        echo "--- kernel messages about USB and serial (last 40)"; dmesg 2>&1 | grep -iE "usb|tty|cdc_acm|ch341|cp210|ftdi" | tail -40
        echo "--- check"; do_check 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
    } 2>&1 | scrub > "$b/system.txt"
    progress_bar 1 4 "Bundle 2 of 4: config files"
    cp "$(CONF_FILE)" "$b/install.conf" 2>/dev/null
    for f in "$CONFIG_DIR"/wm_*.cfg "$CONFIG_DIR/printer.cfg" "$CONFIG_DIR/moonraker.conf"; do [ -f "$f" ] && scrub < "$f" > "$b/config/$(basename "$f")"; done
    progress_bar 2 4 "Bundle 3 of 4: logs"
    for f in klippy moonraker; do [ -f "$INSTALL_HOME/printer_data/logs/$f.log" ] && tail -n 400 "$INSTALL_HOME/printer_data/logs/$f.log" | scrub > "$b/logs/$f.log"; done
    [ -d "$BACKUP_ROOT" ] && ls -1 "$BACKUP_ROOT" > "$b/backups-list.txt" 2>/dev/null
    cat > "$b/README.txt" <<E
This bundle was made by ./installer.sh --support-bundle. Passwords, tokens, keys, Wi-Fi names, private IP and MAC addresses
were removed from the text files. Gcode files and backups are NOT included. Please look through it before sharing.
E
    progress_bar 3 4 "Bundle 4 of 4: packing the file"
    tar czf "$out" -C "$w" ace-support; rm -rf "$w"; chmod 600 "$out"
    progress_bar 4 4 "Done"
    print_success "Saved $out ($(du -h "$out" | cut -f1)). Look through it, then send it along with your question."
}

# ============================================================================
# Update without git, and the numbered menu
# ============================================================================

RAW_URL="https://raw.githubusercontent.com/ducati1198/wm-ultra-fluidd-acepro-panel/main"
TARBALL_URL="https://github.com/ducati1198/wm-ultra-fluidd-acepro-panel/archive/refs/heads/main.tar.gz"

latest_version() { # newest version on GitHub (reads only the VERSION file)
    [ -n "${ACE_TEST_NEW_VERSION:-}" ] && { echo "$ACE_TEST_NEW_VERSION"; return 0; }
    command -v curl >/dev/null 2>&1 || return 1
    curl -fsS --max-time 15 "$RAW_URL/VERSION" 2>/dev/null | tr -d '[:space:]'
}

do_check_updates() {
    local new; print_header "What is new"
    new="$(latest_version || true)"
    [ -n "$new" ] || die_with_fix "could not reach GitHub" "check the internet connection (curl -I https://github.com), then try again"
    echo "  This download: v$VERSION     newest on GitHub: v$new"
    if [ "$new" = "$VERSION" ]; then print_success "You have the newest version."; return 0; fi
    print_info "A newer version is available. Newest changes:"
    if [ -n "${ACE_TEST_NEW_VERSION:-}" ]; then echo "  (test: no download)"; else
        curl -fsS --max-time 15 "$RAW_URL/CHANGELOG.md" 2>/dev/null | sed -n '1,/^## /{/^## /!p}; /^## /{p; :a; n; /^## /q; p; ba}' | head -25 | sed 's/^/  /'
    fi
    echo "  Update with: ./installer.sh --get-latest   (then ./installer.sh --update to apply it)"
}

do_get_latest() { # refresh THIS folder from GitHub (git pull, or a tarball when there is no git)
    local tmp rc
    print_header "Downloading the newest installer files"
    if [ -d "$REPO_DIR/.git" ] && command -v git >/dev/null 2>&1; then
        (cd "$REPO_DIR" && git pull --ff-only) || die_with_fix "git pull did not work" "run: cd $REPO_DIR && git status"
    else
        command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1 || die_with_fix "curl or tar is missing" "sudo apt-get install -y curl tar"
        tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"; exit 130' INT TERM
        if [ -n "${ACE_TEST_TARBALL:-}" ]; then cp "$ACE_TEST_TARBALL" "$tmp/x.tgz"
        else curl -fsSL --max-time 120 "$TARBALL_URL" -o "$tmp/x.tgz" || { rm -rf "$tmp"; die_with_fix "download failed" "check the internet connection"; }; fi
        mkdir "$tmp/x" && tar -xzf "$tmp/x.tgz" -C "$tmp/x" --strip-components=1 && [ -f "$tmp/x/installer.sh" ] || { rm -rf "$tmp"; die_with_fix "the download is not the installer" "try again later"; }
        cp -a "$tmp/x/." "$REPO_DIR/"; rc=$?; rm -rf "$tmp"; trap - INT TERM   # the downloaded copy never stays in /tmp
        [ "$rc" = 0 ] || die_with_fix "could not copy the new files into $REPO_DIR" "check the folder permissions"
    fi
    VERSION="$(tr -d '[:space:]' < "$REPO_DIR/VERSION" 2>/dev/null || echo dev)"
    print_success "Installer files are now v$VERSION. Apply them to the printer with ./installer.sh --update"
}

# ============================================================================
# Free up disk space
# ============================================================================
FREE_NEED_MB=300
declare -a FS_ID FS_LABEL FS_KB FS_WARN FS_SUDO
fs_add() { FS_ID+=("$1"); FS_LABEL+=("$2"); FS_KB+=("$3"); FS_WARN+=("$4"); FS_SUDO+=("$5"); }
fs_kb() { local k; [ $# -gt 0 ] || { echo 0; return; }; k="$(du -sk "$@" 2>/dev/null | awk '{s+=$1} END{print s+0}')"; echo "${k:-0}"; }
fs_tmpdirs() {   # leftover downloads of this installer in /tmp: only folders made by this user that hold a copy of wm-ultra-rpi
    local base="${ACE_TEST_TMP:-/tmp}" d
    for d in "$base"/tmp.*; do [ -d "$d" ] && [ -f "$d/VERSION" ] && [ -d "$d/orca_plugin" ] && [ -f "$d/installer.sh" ] && [ "$(stat -c %U "$d" 2>/dev/null)" = "$(id -un)" ] && echo "$d"; done
}
fs_scan() {
    FS_ID=(); FS_LABEL=(); FS_KB=(); FS_WARN=(); FS_SUDO=()
    local kb d list=()
    while read -r d; do [ -n "$d" ] && list+=("$d"); done < <(fs_tmpdirs)
    if [ ${#list[@]} -gt 0 ]; then kb="$(fs_kb "${list[@]}")"; fs_add tmp "Leftover installer downloads in /tmp (${#list[@]} folder(s))" "$kb" "Copies of this installer that an older 'Update now' left behind. Nothing else is in them." 0; fi
    kb="$(fs_kb "$INSTALL_HOME/.cache/pip")"; fs_add pip "pip download cache (~/.cache/pip)" "$kb" "Downloaded Python packages. They are downloaded again only if you reinstall something." 0
    if [ "$TESTING" = 1 ]; then kb="${ACE_TEST_APT_KB:-0}"; else kb="$(fs_kb /var/cache/apt/archives)"; fi
    fs_add apt "apt package cache (/var/cache/apt/archives)" "$kb" "Downloaded .deb files of packages that are already installed. Installed programs are not touched." 1
    if [ "$TESTING" = 1 ]; then kb="${ACE_TEST_JOURNAL_KB:-0}"; else kb="$(fs_kb /var/log/journal)"; kb=$(( kb > 51200 ? kb - 51200 : 0 )); fi
    fs_add journal "Old system log history (keeps the newest 50 MB)" "$kb" "Erases older system messages (journalctl). Only useful when looking for an old problem." 1
    kb="$(fs_kb $(ls "$INSTALL_HOME/printer_data/logs"/*.log.* 2>/dev/null))"; fs_add oldlogs "Old rotated printer logs (~/printer_data/logs/*.log.*)" "$kb" "Older copies of klippy/moonraker logs. The current logs stay." 0
    # (tests only ever touch a copy of the installer folder, never the real repository)
    if [ -d "$REPO_DIR/.git" ] && case "$(basename "$REPO_DIR")" in wm-ultra-fluidd-acepro-panel*) true ;; *) false ;; esac && { [ "$TESTING" != 1 ] || [ "${ACE_TEST_REFRESH_REPO:-0}" = 1 ]; }; then kb="$(fs_kb "$REPO_DIR/.git")"; fs_add gitdir "Git history of the downloaded installer ($REPO_DIR/.git)" "$kb" "After this, 'git pull' no longer works in that folder; 'Update now' in the menu downloads the newest files instead." 0; fi
}
fs_free_text() { echo "  Free space now: $(disk_free_mb) MB   (the install needs about $FREE_NEED_MB MB)"; }
fs_do() {   # id
    case "$1" in
        tmp) local d; while read -r d; do [ -n "$d" ] && rm -rf "$d"; done < <(fs_tmpdirs) ;;
        pip) rm -rf "$INSTALL_HOME/.cache/pip" ;;
        apt) sudo_run apt-get clean ;;
        journal) sudo_run journalctl --vacuum-size=50M ;;
        oldlogs) rm -f "$INSTALL_HOME/printer_data/logs"/*.log.* ;;
        gitdir) rm -rf "$REPO_DIR/.git" ;;
    esac
}
do_free_space() {   # lists what can be erased safely, with sizes and a warning for each; erases only what you pick and confirm
    print_header "Free up disk space"
    fs_free_text
    fs_scan
    local i n=0 idx=() ans pick=() total=0 k
    for i in "${!FS_ID[@]}"; do
        [ "${FS_KB[$i]}" -ge 1024 ] || continue
        n=$((n+1)); idx+=("$i")
        printf '   %s) %-62s %5s MB%s\n' "$n" "${FS_LABEL[$i]}" "$(( FS_KB[i] / 1024 ))" "$([ "${FS_SUDO[$i]}" = 1 ] && echo '  (asks for sudo)')"
        echo -e "      ${DIM}${FS_WARN[$i]}${NC}"
    done
    [ "$n" -gt 0 ] || { print_info "Nothing safe to erase was found. Free space yourself: old files in ~/printer_data/gcodes, or other large files (du -xh ~ --max-depth=1 | sort -rh | head)."; return 0; }
    echo "  Your gcode files, your settings, KlipperScreen and the factory software are never in this list."
    if false; then ans="all"; else read -r -p "  Type the numbers to erase (for example 1 3), 'all', or press Enter to cancel: " ans || ans=""; fi
    ans="$(echo "$ans" | tr ',' ' ')"
    [ -n "$ans" ] || { echo "  Nothing was erased."; return 0; }
    if [ "$ans" = all ]; then pick=("${idx[@]}"); else
        for k in $ans; do [[ "$k" =~ ^[0-9]+$ ]] && [ "$k" -ge 1 ] && [ "$k" -le "$n" ] && pick+=("${idx[$((k-1))]}") || { print_warning "'$k' is not in the list."; return 0; }; done
    fi
    echo; echo -e "  ${YELLOW}This will ERASE:${NC}"
    for i in "${pick[@]}"; do echo "    - ${FS_LABEL[$i]}  (about $(( FS_KB[i] / 1024 )) MB)"; echo -e "      ${DIM}${FS_WARN[$i]}${NC}"; total=$((total + FS_KB[i])); done
    if [ "$DRY" = 1 ]; then echo -e "  ${DIM}(dry run: nothing is erased)${NC}"; return 0; fi
    ask_yn "Erase these now? About $((total/1024)) MB will be freed" N || { echo "  Nothing was erased."; return 0; }
    local fi_=0; for i in "${pick[@]}"; do progress_bar "$fi_" "${#pick[@]}" "Erasing (step $((fi_+1)) of ${#pick[@]})"; fs_do "${FS_ID[$i]}"; fi_=$((fi_+1)); done
    progress_bar "${#pick[@]}" "${#pick[@]}" "Done"
    [ "$TESTING" = 1 ] && export ACE_TEST_DISK_MB=$(( ${ACE_TEST_DISK_MB:-4000} + total/1024 ))
    print_success "Erased. Free space now: $(disk_free_mb) MB"
}

disk_free_mb() { [ "$TESTING" = 1 ] && { echo "${ACE_TEST_DISK_MB:-4000}"; return; }; df -Pm "$INSTALL_HOME" | awk 'NR==2{print $4}'; }
check_disk_space() {
    local free; free="$(disk_free_mb)"
    if [ "${free:-0}" -le "$FREE_NEED_MB" ] && { [ -t 0 ] || [ "${ACE_TEST_FREE_OFFER:-0}" = 1 ]; } && [ "$DRY" != 1 ]; then
        print_warning "Only ${free} MB free; the install needs about $FREE_NEED_MB MB."
        echo "  I can look for files that are safe to erase and show you each one before anything is deleted."
        ask_yn "Look for files to erase now?" Y && { do_free_space; free="$(disk_free_mb)"; }
    fi
    [ "${free:-0}" -gt "$FREE_NEED_MB" ] || die_with_fix "only ${free} MB free." "free space first: ./installer.sh --free-space  (it shows what is safe to erase and asks before deleting)"
    print_success "Disk space ok (${free} MB free)"
}

menu_item() { printf '   %s) %-30s %b%s%b\n' "$1" "$2" "$DIM" "$3" "$NC"; }
menu_read() { local a; read -r -p "  $1 " a || return 1; REPLY_MENU="$(echo "$a" | tr -d '[:space:]')"; return 0; }
menu_sub() { # run this script again with options, then pause so the output can be read
    echo; bash "$SCRIPT_DIR/installer.sh" "$@"; echo
    [ -t 0 ] && read -r -p "  Press Enter to go back to the menu " _ || true
}
menu_bad() { echo "  Choose a number from the list."; }

menu_update() {
    while true; do
        echo; echo -e "${BLUE}Update${NC}"
        menu_item 1 "See what is new" "reads GitHub, changes nothing"
        menu_item 2 "Update now" "downloads the newest files, then applies them (backup first)"
        menu_item 0 "Back" ""
        menu_read "Choose:" || return 0
        case "$REPLY_MENU" in
            1) menu_sub --check-updates ;;
            2) menu_sub --get-latest
               local cd_="${CONFIG_DIR:-$INSTALL_HOME/printer_data/config}"
               if [ ! -f "$cd_/$CONF_NAME" ] && [ ! -f "$cd_/wm_ace.cfg" ]; then   # nothing installed yet: the installer files are current, there is nothing to update
                   echo; print_info "Nothing is installed on this machine yet, so there is nothing to update. The installer files above are the newest. Go back and choose 1 (Install)."
                   [ -t 0 ] && read -r -p "  Press Enter to go back to the menu " _ || true
               else menu_sub --update; fi
               exec bash "$SCRIPT_DIR/installer.sh" --menu ;;   # restart the menu so the new version is the one running
            0|"") return 0 ;; *) menu_bad ;;
        esac
    done
}

menu_fix() {
    while true; do
        echo; echo -e "${BLUE}Check and fix${NC}"
        menu_item 1 "Check" "reports problems, changes nothing"
        menu_item 2 "Repair" "restores links and include lines, then checks again"
        menu_item 3 "Doctor" "finds problems and offers a fix for each (asks first)"
        menu_item 4 "Support bundle" "a .tgz of logs and config with passwords and addresses removed"
        on_factory_board && menu_item 5 "Fix the clock and apt" "factory screen board only: automatic time sync and the Debian archive"
        menu_item 0 "Back" ""
        menu_read "Choose:" || return 0
        case "$REPLY_MENU" in
            1) menu_sub --check ;;
            2) menu_sub --repair; menu_sub --check ;;
            3) menu_sub --doctor ;;
            4) menu_sub --support-bundle ;;
            5) on_factory_board && menu_sub --fix-clock || menu_bad ;;
            0|"") return 0 ;; *) menu_bad ;;
        esac
    done
}

menu_backup() {
    local d n
    while true; do
        echo; echo -e "${BLUE}Backup and restore${NC}"
        echo "  Backups are made automatically before every install, update and uninstall, in $BACKUP_ROOT"
        menu_item 1 "List my backups" ""
        menu_item 2 "Restore the newest backup" "puts back the files saved before the last change"
        menu_item 3 "Restore a backup from the list" "pick one"
        menu_item 0 "Back" ""
        menu_read "Choose:" || return 0
        case "$REPLY_MENU" in
            1) ls -d "$BACKUP_ROOT"/wm-*/ 2>/dev/null | sed 's#/$##' | sort || true; [ -d "$BACKUP_ROOT" ] || echo "  No backups yet." ;;
            2) menu_sub --undo ;;
            3) mapfile -t BK < <(ls -d "$BACKUP_ROOT"/wm-*/ 2>/dev/null | sed 's#/$##' | sort)
               if [ "${#BK[@]}" -eq 0 ]; then echo "  No backups yet."; continue; fi
               local i=1; for d in "${BK[@]}"; do echo "   $i) $d"; i=$((i+1)); done
               menu_read "Number:" || return 0; n="$REPLY_MENU"
               if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#BK[@]}" ]; then menu_sub --undo "${BK[$((n-1))]}"; else menu_bad; fi ;;
            0|"") return 0 ;; *) menu_bad ;;
        esac
    done
}

menu_main() {
    [ -t 0 ] || [ "${ACE_MENU_TEST:-0}" = 1 ] || die_with_fix "the menu needs a terminal." "run it in an ssh session, or use the options (--help)."
    while true; do
        echo; echo -e "${BLUE}WonderMaker Ultra panel / ACE Pro${NC}   installer v$VERSION"
        menu_item 1 "Install" "asks a few plain questions, shows the plan, then asks"
        menu_item 2 "Update" "see what is new, then update (your tuned values are kept)"
        menu_item 3 "Check and fix" "check, repair, doctor, support bundle"
        menu_item 4 "Backup and restore" "list backups, put one back"
        menu_item 5 "Dry run of the install" "shows what would change, changes nothing"
        menu_item 6 "Uninstall" "removes everything the installer added (saved first)"
        menu_item 7 "Free up disk space" "shows what is safe to erase (sizes, warnings), erases only what you pick"
        menu_item 0 "Exit" ""
        menu_read "Choose:" || return 0
        case "$REPLY_MENU" in
            1) menu_sub --install ;;
            2) menu_update ;;
            3) menu_fix ;;
            4) menu_backup ;;
            5) menu_sub --dry-run ;;
            6) menu_sub --uninstall ;;
            7) menu_sub --free-space ;;
            0|"") return 0 ;;
            *) menu_bad ;;
        esac
    done
}

usage() { sed -n '/^# \.\/installer\.sh/p' "$0" | sed 's/^# //'; }

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --menu) MODE=menu ;;
            --free-space) MODE=freespace ;;
            --doctor) MODE=doctor ;;
            --support-bundle) MODE=bundle ;;
            --fix-clock) MODE=fixclock ;;
            --install) MODE=install ;;
            --check-updates) MODE=whatsnew ;;
            --get-latest) MODE=getlatest ;;
            --update) MODE=update ;;
            --check) MODE=check ;;
            --repair) MODE=repair ;;
            --undo) MODE=undo; if [ "${2:-}" ] && [ "${2:0:2}" != "--" ]; then UNDO_ARG="$2"; shift; fi ;;
            --uninstall) MODE=uninstall ;;
            --dry-run) DRY=1 ;;
            --klipper-dir) KLIPPER_DIR="${2:-}"; shift ;;
            --config-dir) CONFIG_DIR="${2:-}"; shift ;;
            --version) echo "$VERSION"; exit 0 ;;
            -h|--help) usage; exit 0 ;;
            *) echo "Unknown option: $1"; usage; exit 64 ;;
        esac
        shift
    done
}

main() {
    [ $# -eq 0 ] && { [ -t 0 ] || [ "${ACE_MENU_TEST:-0}" = 1 ]; } && set -- --menu
    parse_args "$@"
    command -v python3 >/dev/null 2>&1 || die_with_fix "python3 is not installed" "sudo apt-get install -y python3"
    local rc=0
    case "$MODE" in
        menu) menu_main ;;
        freespace) do_free_space ;;
        doctor) do_doctor ;;
        bundle) do_support_bundle ;;
        fixclock) on_factory_board && fix_factory_board || print_info "This is not the factory screen board, so there is nothing to fix." ;;
        whatsnew) do_check_updates ;;
        getlatest) do_get_latest ;;
        install|update) do_install ;;
        check) do_check ;;
        repair) do_repair ;;
        undo) do_undo "$UNDO_ARG" ;;
        uninstall) do_uninstall ;;
    esac
    rc=$?
    live_bar_stop
    return $rc
}

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
