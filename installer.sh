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
# ./installer.sh --undo [DIR]  put back the files saved before the last install
# ./installer.sh --uninstall   remove everything the installer added (saved first, --undo brings it back)
# ./installer.sh --dry-run     go through the questions, show what would change, change nothing
# ./installer.sh --help
#
# What this installer never does:
#   - It never flashes any board (main board, toolheads, hub). No firmware is touched.
#   - It never starts or restarts Klipper unless you answer yes to that one question.
#   - It never changes a WonderMaker file. Your printer.cfg only gets three include lines.
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

CFG_FILES=(wm_ace_driver.cfg wm_ace.cfg wm_endless.cfg)
INCLUDE_LINES=("[include wm_ace_driver.cfg]" "[include wm_ace.cfg]" "[include wm_endless.cfg]")
# Values the installer keeps when you update (file:key). "var" keys are `variable_<key>:` lines, "opt" keys are `<key>:` lines.
KEEP_VARS_ACE=(max_total_mm hub_to_head_mm tail_mm fast_speed slow_speed retract_speed tick_s fast_timeout_s slow_timeout_s auto)
KEEP_VARS_ENDLESS=(hop prime_mm prime_speed)
KEEP_OPTS_DRIVER=(feed_speed retract_speed max_dryer_temperature)

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

die_with_fix() {
    local msg="$1" fix="$2"
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

ensure_include() { # "[include x.cfg]"  - goes right after the previous include we added, or after zru-s.cfg
    local line="$1" pc="$CONFIG_DIR/printer.cfg" tmp after="$2"
    grep -qF -- "$line" "$pc" && return 0
    backup_path "$pc"
    tmp="$(mktemp)"
    awk -v line="$line" -v after="$after" '
        { print }
        !d && index($0, after) == 1 { print line; d=1 }
        END { if (!d) print "MISSING-INCLUDE-ANCHOR" }' "$pc" > "$tmp" && cat "$tmp" > "$pc" && rm -f "$tmp"
    if grep -qx "MISSING-INCLUDE-ANCHOR" "$pc"; then
        sed -i '/^MISSING-INCLUDE-ANCHOR$/d' "$pc"
        add_before_save_config "$pc" "$line"
    fi
    print_success "Added $line to printer.cfg"
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

install_fluidd_panel() {
    local fluidd_dir="$1" zip="$SCRIPT_DIR/fluidd/fluidd-v1.37.7-zr-ace.zip" backup
    [ -f "$zip" ] || { warn_later "Fluidd build not found: $zip"; return 1; }
    if [ -f "$zip.sha256" ] && ! (cd "$SCRIPT_DIR/fluidd" && sha256sum -c "$(basename "$zip.sha256")" >/dev/null 2>&1); then
        warn_later "Checksum of the Fluidd build does not match. The panel was not installed."; return 1
    fi
    [ -d "$fluidd_dir" ] || { warn_later "Fluidd folder not found: $fluidd_dir"; return 1; }
    backup="${fluidd_dir}_backup_$(timestamp)"
    cp -a "$fluidd_dir" "$backup" && echo "FLUIDD $fluidd_dir $backup" >> "$BACKUP_DIR/manifest.txt"
    print_success "Backed up Fluidd → $backup"
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

    [ "$HAVE_ACE" = 1 ] && link_driver
    apply_stage
    ensure_includes
    [ "$WANT_FLUIDD" = 1 ] && install_fluidd_panel "$FLUIDD_DIR"
    save_answers
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
    for l in wm_ace_driver.cfg wm_ace.cfg wm_endless.cfg; do
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
    grep -qE '^\s*\[include\s+wm_(ace_driver|ace|endless)\.cfg\]' "$CONFIG_DIR/printer.cfg" 2>/dev/null && echo "  EDIT   printer.cfg (the three ACE include lines)"
    echo
    print_info "Left alone: every WonderMaker file, the Fluidd panel (use --undo to put the old Fluidd back), Python packages."
    why "everything is saved first. ./installer.sh --undo puts it all back."
    [ "$DRY" = 1 ] && { print_info "Dry run: nothing removed."; return 0; }
    ask_yn "Remove the ACE Pro install?" N || { print_info "Cancelled. Nothing changed."; return 0; }

    BACKUP_DIR="$BACKUP_ROOT/wm-$(timestamp)-uninstall"
    mkdir -p "$BACKUP_DIR" && : > "$BACKUP_DIR/manifest.txt"
    remove_include_lines
    for f in "${CFG_FILES[@]}" "$CONF_NAME"; do
        if [ -e "$CONFIG_DIR/$f" ]; then backup_path "$CONFIG_DIR/$f"; rm -f "$CONFIG_DIR/$f"; print_success "Removed $f"; fi
    done
    for f in ace temperature_ace.py virtual_pins.py; do remove_link "$x/$f" "$f"; done
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
    while IFS= read -r line; do
        kind="${line%% *}"; a="${line#* }"
        case "$kind" in
            MOD)  mkdir -p "$(dirname "$a")"; rm -rf "$a"; cp -a "$dir/files$a" "$a" && print_success "Restored $a" ;;
            NEW)  rm -rf "$a" && print_success "Removed $a (it was new)" ;;
            LINK) b="${a#* }"; a="${a%% *}"; rm -f "$a"; [ "$b" != "-" ] && ln -s "$b" "$a"; print_success "Link $a put back" ;;
            FLUIDD) b="${a#* }"; a="${a%% *}"; if [ -d "$b" ]; then rm -rf "$a" && cp -a "$b" "$a" && print_success "Fluidd restored from $b"; fi ;;
        esac
    done < <(tac "$dir/manifest.txt")
    print_success "Done. Restart Klipper when you next use the printer."
}

do_check() {
    local bad=0 f x state py have
    find_dirs
    echo -e "${BLUE}WonderMaker Ultra panel / ACE Pro check${NC}   installer v$VERSION"
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
    x="$KLIPPER_DIR/klippy/extras"
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
    if [ -d "$INSTALL_HOME/fluidd/assets" ]; then
        grep -rlq "ACE feeder" "$INSTALL_HOME/fluidd/assets" 2>/dev/null && print_success "Fluidd has the Toolheads panel" || print_info "Fluidd is not the panel build"
    fi
    if command -v curl >/dev/null 2>&1 && [ "$TESTING" = 0 ]; then
        state="$(curl -s -m 3 "$MOONRAKER_URL/printer/info" 2>/dev/null | python3 -I -c 'import sys,json; print(json.load(sys.stdin)["result"]["state"])' 2>/dev/null || true)"
        echo; [ -n "$state" ] && print_info "Klipper state: $state" || print_info "Moonraker is not answering on $MOONRAKER_URL (Klipper may be stopped)"
    fi
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
    [ "$HAVE_ACE" = 1 ] && link_driver
    ensure_includes
    print_success "Repair finished. Run ./installer.sh --check"
}

usage() { sed -n '/^# \.\/installer\.sh/p' "$0" | sed 's/^# //'; }

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
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
    parse_args "$@"
    command -v python3 >/dev/null 2>&1 || die_with_fix "python3 is not installed" "sudo apt-get install -y python3"
    case "$MODE" in
        install|update) do_install ;;
        check) do_check ;;
        repair) do_repair ;;
        undo) do_undo "$UNDO_ARG" ;;
        uninstall) do_uninstall ;;
    esac
}

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
