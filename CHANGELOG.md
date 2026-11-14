# Changelog

## 1.7.8

- **OrcaSlicer plugin 0.7.1 (`orca_plugin/spool_toolhead_mapper.py`).** The WonderMaker toolheads win again when a printer has both an ACE Pro and the four toolhead sensors (the ZR Ultra-S with an ACE Pro had been shown as an ACE printer). New: an address box per printer preset (Orca did not always give the plugin the print host), quote marks removed from the host, the panel notices a printer switch and filament changes, reads the printer again every 30 seconds, and shows toolhead colours and materials like the ZR Tools screen (`zr_tN_mat`, `zr_tN_color`, and the 11 materials added in 1.7.6). A `printer_kind` setting (auto, wm, ace), a status line under the buttons and a log file (`~/.spool_toolhead_mapper.log`) for troubleshooting. 12 new tests. The file must keep the name `spool_toolhead_mapper.py` (a dot or space in the name stops Orca from activating it).

## 1.7.7

- **The "Z offset" button is removed from the tool window** (Hardware actions). The Z offset calibration (`CALIBRATE_TOOL_Z_OFFSET`) is started from the touchscreen. New Fluidd zip, patch and checksum.

## 1.7.6

- **More filament materials in the tool window** (Material type): PLA+, PLA-CF, PETG-CF, PA, PA-CF, PC, ABS-CF, PA-GF, PC-ABS, PP and BVOH. They are added at the END of the list, so the first 16 keep their place and the colours and materials already saved in `tmt1.ini` do not change. The factory touchscreen may not know the new ones and then shows that slot as not set. New Fluidd zip, patch and checksum.

## 1.7.5

- **`z_rise` before every X/Y move of the ACE macros** (the bed is lowered first so the nozzle cannot scratch it): at the start of `ACE_WM_LOAD` and `ACE_WM_UNLOAD`, and in `_WM_ACE_HOME` before the homing and the hot-nozzle wipe, and in `_WM_ACE_HOME_Z` before the move to the middle of the bed. `z_rise` is WonderMaker's own macro; WM_Ultra_Vanilla_Klipper 2.7.4 fixes it for upstream Klipper (it never did anything there) and adds it to the tool lock and unlock and the wipe macros.

## 1.7.4

- **The `SET_GCODE_OFFSET` wrapper is in both `rpi_ace.cfg` and WM_Ultra_Vanilla_Klipper 2.7.3 (`rpi_pi.cfg`).** The ACE panel works on its own, and with both installed Klipper merges the two identical sections into one macro.

## 1.7.2

Quick homing with the tool on the carriage, an ACE auto load switch, and Fluidd hardware-action fixes (needs WM_Ultra_Vanilla_Klipper 2.7.2 for the LED part).

- **Quick homing (`_WM_ACE_HOME`, `_WM_ACE_HOME_Z`)**: `ACE_WM_LOAD` and `ACE_WM_UNLOAD` home X, Y and Z with the tool that is already on the carriage instead of docking it and taking T0. A hot nozzle (above 150 C) is wiped first, then homed. It falls back to WonderMaker's own `G28` when a print runs or is paused, the fail flag is set, all tools are docked, or the stored tool offset is missing or too large.
- **`SET_GCODE_OFFSET` wrapper**: skips the offset move while Z is not homed, so tool changes no longer fail with "Must home axis first".
- **ACE auto load switch**: new `ACE_Auto_Load` output pin (Fluidd Outputs) in `rpi_ace_driver.cfg`; `ACE_WM_AUTO ENABLE=0|1` sets it, the choice is remembered across restarts, and the watcher only auto loads when it is on.
- **Fluidd panel**: "Auto load" switch in the ACE section of the Toolheads card; Park and Select in Hardware actions need only X and Y homed; Purge asks to home first with a Home button; Load and Unload are hidden when an ACE is present (shown again without one).

## 1.7.1

Automatic load and unload work again on upstream Klipper (needs WM_Ultra_Vanilla_Klipper 2.7.1 for the LED part).

- **`ACE_WM_LOAD`** picks up the tool first (`T<n>`), so WonderMaker switches on that tool's filament sensor and its own load runs when the filament arrives. It homes all axes first when they are not homed (and clears the tool Z offset without moving).
- **`ACE_WM_UNLOAD`** homes all axes first when they are not homed, the same way, so the tool change and the park no longer fail with "Must home axis first".
- **`_WM_ACE_GRAB`** heats the tool to 220 C before the first push when it is cold. Upstream Klipper refuses cold extrusion (WonderMaker's Klipper did not), which stopped the load with "Extrude below minimum temp".
- **Runout guard in `extruder0..3.cfg`** (added by `scripts/ace_hooks.py` with the other hooks): the runout macro only pauses while a print runs. An unload while idle no longer shows a failed pause.

## 1.7.0

- **Fluidd panel is now built on Fluidd 1.38.0** (was 1.37.7). New in Fluidd: web-based firmware updates, G-code preview coloured by feature, speed or fan, Moonraker extensions API, TMC5262 support, better websocket reconnection, no runaway file ETA during the start macro, the file list keeps your selection when it refreshes, and more (see the Fluidd 1.38.0 release notes). All the Toolheads card, ACE and Choose toolheads parts are carried over; the patch applies to v1.38.0 with one import line merged. New files: `fluidd/fluidd-v1.38.0-zr-ace.zip`, `.patch`, `.zip.sha256`.
- **The old 1.37.7 build is kept** in `old_backup/fluidd/1.37.7/` (zip, checksum, patch) in case you need to go back. The installer does not use it.

## 1.6.1

- **Fluidd: "ACE Pro support is turned off" banner with a Turn on button.** When the ACE_Pro switch is off (tool changes and slot moves are ignored), the Toolheads card shows a blue banner with a green TURN ON button that switches it back on. Wording for the 4 toolheads: "Toolhead changes (T0-T3) and ACE slot moves are ignored." New Fluidd zip, patch and checksum.

## 1.6.0

- **The config files are now called rpi_ instead of wm_.** `wm_ace_driver.cfg` -> `rpi_ace_driver.cfg`, `wm_ace.cfg` -> `rpi_ace.cfg`, `wm_endless.cfg` -> `rpi_endless.cfg`, `wm_stats.cfg` -> `rpi_stats.cfg`, and the install record `wm-ultra-install.conf` -> `rpi-ultra-install.conf`. The macros inside keep their names (`ACE_WM_ASSIST`, `WM_SET_TOOL_MAP`, ...), so slicer start G-code and your own macros are not affected.
- **Existing installs are renamed by `./installer.sh --update`** (also by `--repair`, `--uninstall`). It saves a backup first (`~/acepro-backup/wm-<time>-rename`, undo with `./installer.sh --undo`), renames the files, changes the `[include ...]` lines in `printer.cfg` and keeps your tuned values. `--check` and `--doctor` tell you when the old names are still there; `--dry-run` changes nothing. Restart Klipper afterwards.
- **Fluidd panel:** the Chamber light button now reads `config/rpi_chamber_light.json` (was `wm_chamber_light.json`). New Fluidd zip and checksum. Update the screen board (WM_Ultra_Vanilla_Klipper 2.6.0) as well, or the button stays hidden until the board uploads the new file name.

## 1.5.22

- **Feed assist on/off for every tool, also during a pause.** New macro `ACE_WM_ASSIST T=0-3 STATE=on|off|toggle`. The Feed assist button in the Fluidd tool window (the Toolheads card, edit a tool) now uses it. A choice made by hand stays until the next print starts or ends, also while the print is paused. Switching one tool on switches the previously active tool off (the ACE has one feed assist at a time). It refuses while the ACE is loading or unloading. Same button on the KlipperScreen tool pages (WM_Ultra_Vanilla_Klipper 2.4.0). New Fluidd zip, patch and checksum.

## 1.5.21

- **Fluidd: the Choose toolheads window reads OrcaSlicer files correctly.** An empty `referenced_tools` list no longer means "no filament is used" (the window said the file had no colour information), and the material list that Moonraker gives as text (`["PLA", "PLA"]`) is read as a list (every row showed a false "Check"). Checked in a browser against a mock printer: List/Map, Saved mappings, Auto-match, Dry spools first, Print as sliced, Cancel and the last choice per file. The map view says "toolhead" instead of "spool". New Fluidd zip, patch and checksum.

## 1.5.19

- **Fluidd: the Choose toolheads window now opens on every Print even when Fluidd has not loaded the file's colour data yet** (before, it could start the print straight away). The window reads the file's details itself. Its subtitle shows the panel version, so you can tell which build the browser is running. New Fluidd zip, patch and checksum.

## 1.5.18

- **Fluidd: the Choose toolheads window opens every time you press Print** (file list, Re-print, status card), like the ACE spool window on the K1 Max. A file without colour data still starts straight away.
- **Choose toolheads window extras:** List / Map view, Saved mappings (also remembers the last choice per file), Auto-match, Dry spools first (starts the ACE dryer, only when an ACE is present) and Print as sliced. New Fluidd zip, patch and checksum.

## 1.5.17

- **The installer removes `[update_manager fluidd]` from `moonraker.conf`.** Moonraker's own Fluidd updater would replace this panel build with stock Fluidd. After the panel is installed the section is removed (a copy of `moonraker.conf` is saved first) and Moonraker is restarted. `./installer.sh --doctor` checks it and offers the same fix. Tests added (131 pass).

## 1.5.16

- README: removed the mentions of a simulated printer (status line, disclaimer, endless-spool note).

## 1.5.15

- **README status updated: tested on a real printer.** The project has now been run on a WonderMaker ZR Ultra-S with an ACE Pro (Fluidd panel, ACE driver, loading and unloading, printing, calibration macros) and the Orca plugin works in OrcaSlicer 2.5. The red "not yet tested" badge, the status line and the disclaimer say so. Things still not tested stay marked (ACE 2 Pro, the items in section 6 "Still unverified"). It still needs a little tweaking.

## 1.5.14

- **Fluidd: CHAMBER LIGHT ON/OFF button beside AIR FILTER in the Toolheads card.** The light is on the TM-T1 screen board, not the Pi. The board's installer (wm-ultra-rpi 1.23.63) runs a small service that toggles it and writes `config/wm_chamber_light.json` (the service address) into Moonraker; the card reads that file and shows the button only when it exists and the board answers. Fluidd v1.37.7 patch series: one new commit appended; zip rebuilt (`pnpm run lint` and `pnpm run build` pass; the series applies cleanly on a fresh v1.37.7). Not tested on the printer yet.

## 1.5.13

- README: new load/unload behaviour, the hook lines in `extruder0..3.cfg`, a list of what was tested on the printer and what is still unverified. The "draft, not tested" note in `wm_ace.cfg` now says what was tested.

## 1.5.12

- **ACE load and unload were reworked** (load and unload tried on a printer; the grab push and feed-assist-off at the end are not yet tested): when the filament trips the tool head sensor the ACE stops feeding, waits one second and turns feed assist on; the extruder gear then grabs the filament with a short slow push before WonderMaker's insert routine, and feed assist is switched off again when that routine is finished. Unload now picks up the tool by itself, forms a tip with the extruder alone (ACE idle, feed assist off), then the ACE pulls the filament back and stops when the slot reports empty. Auto load is held off for a while after an unload. New `config/wm_ace.cfg` macros: `_WM_ACE_HEAD`, `_WM_ACE_GRAB`, `_WM_ACE_HEAD_DONE`, `_WM_ACE_UNLOAD_RUN`; new state `load_final` and variable `hold`. `hub_to_head_mm` default is now 710. Your tuned values are still kept on update.
- **Three hook lines in WonderMaker's `extruder0..3.cfg`** (first line of `insert_gcode`, before `filament_insert`, after `PARK_CURRENT_TOOL`) connect those macros to WonderMaker's insert routine. The installer adds them (idempotent, a copy of each file is saved first, a file that does not look like WonderMaker's is left alone with a warning), `--repair` re-adds them, `--check` and `--doctor` report them, `--uninstall` removes them again. Script: `scripts/ace_hooks.py`.
- Tests: hook checks added (126 pass).

## 1.5.11

- The installer now sorts the printer's macros into Fluidd's macro categories at the end of an install or update (after the Klipper restart question), and with the new `./installer.sh --fluidd-categories`: AcePro (red), Raspberry Pi (blue), WM Ultra Calibration (yellow), Tool Change (green), Filament (orange), ZR Tools (purple), Print (grey), Tests (dark grey) and Timelapse (cyan). `M104`, `M106`, `M107`, `M109`, `M141`, `M190`, `M191`, `M221` and `z_rise` are hidden. New file `scripts/wm_fluidd_categories.py`, which writes to Moonraker's database (Fluidd's `macros` key), so nothing on disk changes.
- Your own choices are never changed: only macros whose Fluidd entry is still the default are sorted, each macro is dealt with once (the names are recorded in Moonraker's database under `wm_ultra`), categories are created only when a macro needs them and reused by name. If Moonraker or Klipper is not ready the install finishes with a warning that says how to run it later. The previous macro settings are saved in `~/acepro-backup/fluidd-macros-before-<date>.json`. Uninstall leaves the categories.
- New tests: `tests/test_fluidd_categories.py` (rules, never-touch-user-changes, a fake Moonraker) and installer checks in `tests/run_tests.sh` (119 pass).

## 1.5.10

- "Update now" no longer prints `syntax error near unexpected token` after the download. The new installer was written over the running script in place, so bash read the new file at the old file's end. The old file is now removed first. The update itself was not harmed, but the message was confusing. This fix takes effect from the update after this one.

## 1.5.9

- The original Fluidd is now saved once, for good, in `~/acepro-backup/original-fluidd` the first time the panel is installed. The installer never deletes or overwrites it (the cleanup of old copies does not touch it). If the panel was installed by an older version, the oldest untouched saved copy is used.
- `--uninstall` now also offers to put the original Fluidd back (default yes). Your Fluidd `config.json` is kept, the panel is saved first, and `--undo` brings it back.

## 1.5.8

- Endless spool: the two status messages in `wm_endless.cfg` no longer contain semicolons. Klipper treats `;` as the start of a comment, which cut the message and gave "Malformed command". The one in `WM_ENDLESS_CONTINUE` would have made a real endless-spool head swap fail.
- `ACE_SELFTEST` now reads the toolhead and RDM sensor names from `[ace]` instead of fixed names, and reports PASS for a missing `_ACE_VARS` when `register_tool_commands` is False (the printer does its own tool changes).

## 1.5.7

- Support bundle: the system report now also has `lsusb -t`, the serial ports in `/dev` (`ttyACM*`, `ttyUSB*`), the list of serial ports the ACE driver sees (name, description, hwid), and the last USB/serial kernel messages. This shows why "No ACE device found" appears even when `lsusb` lists the ACE.

## 1.5.6

- Old saved copies no longer pile up: after an install only the newest 5 Fluidd copies (`fluidd_backup_*`) and the newest 5 backup folders (`~/acepro-backup/wm-*`) are kept. The newest is always kept, so `--undo` still works.

## 1.5.5

- The progress bar no longer repeats itself on a timer (the repeated lines landed on top of questions). It is printed once at the start of each step.

## 1.5.4

- Pressing Ctrl-C during `--get-latest` now removes the downloaded copy from /tmp.

## 1.5.3

- The live bar no longer uses a pinned bottom line (it came out garbled in some phone terminal apps). While a slow step runs, the bar is printed again on its own line every 15 seconds with the time so far.

## 1.5.2

- The live bar now also covers Check, Doctor, support bundle, Undo, the clock fix and Free up disk space.

## 1.5.1

- The progress bar is now live. In a terminal the current bar stays on the last screen line with a spinner and the time the step has taken (`[████░░░░]  20%  Step 3 of 8  / 1m05s`), so a slow step (apt, pip, a download) visibly keeps running. Before, the bar was printed once per step and stayed still. The normal log lines are unchanged, and nothing is drawn when the output is not a terminal.

## 1.5.0

- **Progress bars** during install, repair and uninstall: `[██████░░░░░░]  60%  Step 3 of 5: include lines in printer.cfg`.
- New **Doctor** (`./installer.sh --doctor`, Check and fix > 3): looks at printer.cfg, free disk space, the installed version, the driver links, config files and include lines, and the Fluidd panel. For each problem it offers a fix and asks first. A config file that is there (maybe tuned) is never overwritten; only a missing one is put back.
- New **Support bundle** (`./installer.sh --support-bundle`, Check and fix > 4): a `.tgz` in your home folder with a system report, your Klipper config files and the end of the klippy and moonraker logs. Passwords, tokens, Wi-Fi names, private IP and MAC addresses are removed. Gcode files and backups are not included.
- The clock fix on the factory screen board no longer skips certificate checks: the time fallback reads the `Date` header over plain http. It also asks about automatic time sync only once an hour.

## 1.4.0

- New **Free up disk space**: menu entry 7 and `./installer.sh --free-space`. It lists what is safe to erase with its size and a warning (leftover installer downloads in /tmp, the pip cache, the apt package cache, old system log history, old rotated printer logs, the installer's git history), you type the numbers, it shows "This will ERASE" and asks before deleting. Your gcode files, settings and backups are never listed.
- The install now checks for about 300 MB of free space and, if there is less, offers that cleanup right there, then checks again.

## 1.3.2

- `--get-latest`: the downloaded copy in /tmp is now also removed when copying the files fails (it was the only path that left it behind).

## 1.3.1

- Menu: Update now on a machine where nothing is installed yet no longer ends with a red error. It updates the installer files, says that nothing is installed yet (choose 1 to install), and reopens the menu on the new version.

## 1.3.0

- On the original WonderMaker screen board only (Debian 11 with the factory app `makerbase-client`), the install now starts with the clock and apt: it asks once to turn on automatic time sync (NTP; if no time server answers it sets the clock once from GitHub's reply), points apt at the Debian archive (a copy of `sources.list` is kept) and makes apt ignore the old package-list dates. On a Raspberry Pi or any other machine this step is skipped. Also available alone as `./installer.sh --fix-clock`, and in the menu under Check and fix (shown only on the factory board).

## 1.2.1

- Menu: Update, Update now restarts the menu after the update, so the new version is the one running (no need to quit and reopen). Same as the other two installers.

## 1.2.0

- New numbered menu, same style as the wm-ultra-rpi installers: Install, Update (See what is new / Update now), Check and fix, Backup and restore, Dry run, Uninstall. Run `./installer.sh` with no options at a terminal, or `./installer.sh --menu`.
- New options: `--install` (skip the menu), `--check-updates` (reads only the VERSION and CHANGELOG on GitHub), `--get-latest` (git pull, or a downloaded tarball when there is no git). Update now runs `--get-latest` and then `--update`.
- Scripts and pipes are unaffected: with no terminal the installer installs as before. The installer still never starts Klipper by itself.

## 1.1.1

- README (section 3.2a): how to install on the original WonderMaker screen board, which has no `git`: fix the clock and point apt at the Debian archive, then install git, or download this repository with `curl` (no git needed). Notes on updating without git and on the free USB port for the ACE. No code changes; the installer already works from a downloaded copy.

## 1.1.0

- Version renumbered to 1.1.0 so it matches [acepro-any-klipper](https://github.com/ducati1198/acepro-any-klipper) 1.1.0. No code changes. The earlier numbers below are kept as history.

## 0.3.6

- OrcaSlicer plugin 0.3.0: refreshes by itself when you switch printer preset, keeps your picks per printer between sessions, shows warnings (toolhead used twice, colour clearly different, empty toolhead), and lets you pick an empty WonderMaker toolhead (with a warning).

## 0.3.5

- OrcaSlicer plugin: `orca_plugin/spool_toolhead_mapper.py` (one plugin for the WonderMaker toolheads and ACE Pro printers) replaces `wm_toolhead_mapper.py`, which is removed. README and `orca_plugin/INSTALL.md` use the new names (panel **Spools and Toolheads**, step **Spool and Toolhead Map**). The README download link now points to the `orca_plugin/` folder. Tests updated.

## 0.3.4

- README: "the printer's main board" instead of "replacement main board".

## 0.3.3

- README: new top part with a Quick start, an everyday cheat sheet (check, update, repair, backup, undo, uninstall), a "How it works" diagram (`docs/img/how-it-works.svg`) and a short "If something goes wrong" table. The detailed sections are unchanged.

## 0.3.2

- README fixes to match the installer and what was tested: where the include lines go (above SAVE_CONFIG, after `[save_variables]`), the new macros, first tests and unverified items for the new features, two troubleshooting rows, the extra installer options, and what was tried on a fresh Pi.
- Installer: removed an unused function.

## 0.3.1

- README: step-by-step install of the OrcaSlicer plugin (section 5).

## 0.3.0

All new and **not yet tested on a printer** (macros are checked in simulation, the Fluidd card builds and lints, the Orca plugin helpers are unit-tested with Orca stubbed).

- Endless spool: per-toolhead chain ("If this spool runs out, take over with ..."). New macro `WM_ENDLESS_CHAIN_SET`. The card tries your chain first, then the same colour and material.
- Fluidd card: tool-change progress bar (from WonderMaker's `changing_tool` flag and the dock sensors) and tool-change counters with a Reset button.
- New `wm_stats.cfg`: counters (`_WM_STATS_POLL`, `WM_STATS_RESET`) and the tool-map macro `WM_SET_TOOL_MAP`. The installer adds it and its include line.
- Fluidd "Choose toolheads" also saves `wm_map_file`, so a map written by the Orca plugin (`KEEP_EXISTING=1`) does not override it.
- New OrcaSlicer plugin `orca_plugin/wm_toolhead_mapper.py` (adapted from the ACE Spool Mapper of acepro-any-klipper).
- ACE driver: `moonraker_lane_sync_enabled` is now `True` by default (your own value is kept on `--update`).
- New tests: `tests/test_macros.py`, `tests/test_orca_plugin.py`, and Fluidd unit tests in the patch.

## 0.2.1

- Fix: Klipper stopped with "Unknown config object 'save_variables'". The ACE driver reads `[save_variables]` while it loads, but the include lines sat above that section in `printer.cfg`. The installer now puts them just above the SAVE_CONFIG block, after `[save_variables]`. `./installer.sh --repair` (or `--update`) moves lines installed by 0.2.0.

## 0.2.0

- Fluidd: new **Choose toolheads** window replaces "Print with colours". It looks at the file first and only opens when a colour or material does not match a loaded toolhead; otherwise the print starts at once. One warning per filament, swap by tapping a used toolhead, empty toolheads block the print. Checked with a simulated printer only.

## 0.1.0

First version. Not yet run on a real printer.

- Works without an ACE Pro: the installer asks first, and "no" installs only the Fluidd panel and the optional endless-spool macros.
- Installer `installer.sh`: install, `--update`, `--check`, `--repair`, `--undo`, `--uninstall`, `--dry-run`. Refuses to run on anything but a WonderMaker ZR Ultra config. Never flashes a board and never starts Klipper by itself.
- Installer tests: `bash tests/run_tests.sh` (52 checks against fake homes).
- Config: `wm_ace_driver.cfg`, `wm_ace.cfg` (load, unload, auto-load, feed assist, dryer), `wm_endless.cfg` (experimental endless spool, off by default).
- Fluidd 1.37.7: WonderMaker Toolheads card with the ACE parts inside, dryer presets, endless-spool offer.
- Driver: new `register_tool_commands` option (default `True`) so WonderMaker keeps its own `T0`…`T3`.
- The installer also links `virtual_pins.py` and `temperature_ace.py`, which the driver config needs and which the earlier hand-installed pack did not.
