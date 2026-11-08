# Changelog

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
