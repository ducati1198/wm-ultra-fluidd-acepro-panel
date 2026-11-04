# Changelog

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
