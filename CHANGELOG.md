# Changelog

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
