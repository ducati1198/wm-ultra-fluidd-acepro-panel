# Changelog

## 1.18.0

- **Fluidd build (33 patches): filament colours (F-198 to F-201, F-207).** The tool dialog gets **More colours** with name lists (Orca, Basic, Web CSS, RAL; 430 colours), a **Color Picker**, a White entry and three extra swatches. The exact colour is saved in `zr_tN_color`, the nearest touchscreen swatch in `tmt1.ini`. Black is now named **Black** (it was "Ink black"). The Fluidd zip, patch and checksum are regenerated; the patch is one commit longer.
- **`config/rpi_endless.cfg`: new setting `swap_purge` (F-202, Resume purge after a tool swap).** `_WM_ENDLESS_3` can raise the purge of the resume after an endless-spool swap to `swap_purge` mm when that is longer than the normal resume purge (20 mm), and puts it back to 20 afterwards. The default is 20, so nothing changes until you raise it. Plain RESUME and `WM_RESUME_TOOL` are not touched.
- Goes with installer 2.23.0 (the KlipperScreen side of the colours, the Tools page and the new start purge switch).

## 1.17.0

- **Fluidd build (32 patches): purge window, Resume tool and Load menu buttons.** The Fluidd zip and patch are regenerated. They call the secondary macros by their hidden names, so the endless spool, stats reset, load/unload stop and Z trim buttons keep working after the rename below.
- **Macro renames (F-167).** The secondary macros now start with an underscore and no longer clutter the macro list: `_WM_ENDLESS_SET`, `_WM_ENDLESS_FIXED`, `_WM_ENDLESS_PLAN`, `_WM_ENDLESS_CONTINUE`, `_WM_STATS_RESET`, `_WM_LOAD_STOP`, `_WM_UNLOAD_STOP`, `_ACE_WM_RETRACT`, `_ACE_WM_ASSIST`. README and Fluidd sorter (`FILAMENT_MENUS`) follow.
- **Tool numbers are shown as T1 to T4 (Toolhead 1 to 4)** in every message of `rpi_ace.cfg` and `rpi_endless.cfg`; the macro parameters still use 0 to 3.
- **`config/rpi_ace.cfg`:** `_ACE_WM_RETRACT` starts the watcher before the retract (F-183), `_ACE_WM_ASSIST` for the Feed assist button, the purge location is set before feeding (F-164), a load sets `_WM_LOAD loaded` (F-166).
- **Tests:** 32 checks (was 31).

## 1.16.3

- **`config/rpi_ace.cfg`: shorter limits (F-154).** `max_total_mm` 4000 to 3000 and `hub_to_head_mm` 2000 to 1200 (the real distance after the preload is about 1000 mm, so a failed head sensor now stops the slow feed after 60 s instead of pushing 2000 mm). `tube_full_mm` says it is measured from the ACE back filament port.
- **`config/rpi_ace.cfg`: `ACE_WM_UNLOAD` called while the ACE is busy waits instead of failing (F-153).** Unload T0 then T1 four seconds later gave "ACE busy (unload_hub)" and T1 was not unloaded. Now the second tool goes into a queue (`unload_queue`) and starts by itself when the ACE is free (checked every 2 s, dropped after 10 minutes or when a print starts). While an unload is picking up its tool the ACE also counts as busy (`unloading_since`, at most 10 minutes). New `delayed_gcode _wm_ace_unload_next`.
- **`config/rpi_ace.cfg`: the first load of a tool starts fast (F-152).** Before, the first load of each tool fed slow (20 mm/s) all the way to measure the tube (about 48 s for 930 mm). Now it feeds fast for the full tube length minus the preload (new variables `tube_full_mm` 1450, `preload_mm` 450 and `measure_margin_mm` 40: 1450 - 450 - 60 slow tail - 40 = 900 mm; the measured tubes were 930 and 942 mm), then slow to the tool head, and measures the tube (the fast part counts 90 percent, because the ACE feeds a bit less than the speed says). New variable `measuring` (runtime state). Later loads are unchanged (fast for the saved length minus 60 mm).

## 1.16.2

- **`config/rpi_ace.cfg`: the nozzle heats at the wipe position (F-150).** `_WM_ACE_GRAB` heats a head that is on the carriage through `_WM_GO_WIPE_HEAT`, and `ACE_WM_LOAD` moves the head to the wipe position (`_WM_GO_WIPE`) before the filament starts to feed. Both keep the old behaviour when the helper macros are missing.
- **Fluidd shows the real macro names.** The sorter no longer writes readable names (aliases), so a button is called what the macro is called (`WM_FIRST_RUN_CAL`, not "First Run Calibration"). The 29 aliases written by 1.10.0 to 1.16.1 are cleared once, and only while the entry still holds exactly that name; a name you typed yourself stays. Reload Fluidd to see it. Tests: 5 new checks.
- **`config/rpi_endless.cfg`: the 6 variables that had no comment now have one** (F-146, comments only).
- **The Fluidd sorter knows the new name `WM_NOZZLE_FULL_PID`** (was `WM_NOZZLE_TEMP_CAL`, F-147): it goes into RPI Calibration.

## 1.16.1

- **`--fluidd-categories` waits up to 60 s for Klipper to be ready** (it used to wait 0 s, so a run right after a start said "not done"). The sorter already creates Fluidd's macro settings when Fluidd was never opened.

## 1.16.0

All backups of this installer are in one folder, `~/ultra-backup`, sorted by type (item 36b). Tested with the installer test suite (183 passed) and on a Raspberry Pi.

- **`installer.sh`:** the undo folders (`wm-<date>`) and the saved original Fluidd are now in `~/ultra-backup/installer/acepro-panel` (was `~/acepro-backup`), the saved copies of the Fluidd web page in `~/ultra-backup/fluidd-page/<date>` (was `~/fluidd_backup_*`), the Fluidd macro lists in `~/ultra-backup/fluidd-macros/<date>`. New `migrate_backup_places` moves the old folders there once (install, update, undo, uninstall, repair, doctor, check), writes each move to `~/ultra-backup/INDEX.txt` and rewrites the Fluidd paths in the old undo manifests, so `--undo` keeps working. Nothing is deleted. The saved original Fluidd is still never deleted; the newest 5 undo folders and 5 Fluidd copies are kept.
- **`installer.sh`: the user that runs the installer is put into the `sudo` group automatically (item 35).** New `ensure_sudo_group`, run at the start of every install and update. Same behaviour as the load cell V2 installer: when the user is not in the `sudo` group it is added (`usermod -aG sudo`), without a question; it takes effect at the next login. Nothing is done when the user is already in the group or when the installer runs as root; a dry run only says what it would do. New tests (5).
- **Tests:** the backup tests use the new places; new tests for the move (undo folder, original Fluidd, Fluidd copy, macro list, manifest paths, second run, dry run).
- The vanilla Klipper installer (the version that goes out with this one) protects `~/ultra-backup/installer/acepro-panel` from its size limits.

## 1.15.0

The ACE unload parks the tool, and a load that hits the tool head in its fast part no longer makes the next load slow. Tested on a ZR Ultra-S with an ACE Pro.

- **`config/rpi_ace.cfg`, `_wm_ace_tick` (F-118, B-068):** after an ACE unload (both finish branches) the tool is parked with `PARK_CURRENT_TOOL` when no print is running or paused. The ACE unload from the Load/Unload buttons of ZR Tools left the tool on the carriage before.
- **`config/rpi_ace.cfg`, `_WM_ACE_HEAD` (F-123, B-071):** when the filament reached the tool head in the fast part, the saved tube length was set to 0 and the next load measured it again, slowly (20 mm/s). That slow measurement comes out too long (the ACE feeds less than its speed says: T2 measured 1518 mm, really about 1200), so the next fast part hit the tool head again and every load stayed slow. The saved length is now what the fast part really fed (time x speed x 0.9); only an estimate under 300 mm is set to 0. A load of T2 took 31 s instead of 77 s.
## 1.14.0

Fluidd Toolheads card on a phone, and the ACE unload with the shared tip forming. Tested on a ZR Ultra-S with an ACE Pro; the Fluidd changes were checked on an iPhone.

- **Fluidd panel rebuilt** (new zip, patch 31 of 31 and checksum): the endless spool section is one column on a narrow card (labels and switches on their own lines, ACE spools, circle, chips under it); the toolhead tiles show the Tangle / Head / Dock lights one under the other and "READY" on a narrow tile; the chamber row (value, field, Set, Off) sits on its own line and "CHAMBER LIGHT" reads "LIGHT" on a card narrower than 520 px. Done with container queries, so it follows the card width (a narrow dashboard column on a computer gets it too). A wide card is unchanged.
- **`config/rpi_ace.cfg`, `_WM_ACE_UNLOAD_RUN`:** when the macro `_WM_UNLOAD_TIP` exists (WM_Ultra_Vanilla_Klipper `zr_tools.cfg`) the ACE unload forms the tip with it at the wipe area, at the saved filament temperature of the tool. Without it the old moves are used, so this file still works alone.

## 1.13.0

Pictures in a Fluidd window, and the tool setter position helper of WM_Ultra_Vanilla_Klipper 2.14.0 in the macro categories. Tested on a ZR Ultra-S.

- **Fluidd panel rebuilt** (new zip, patch 29 of 29 and checksum): a macro window can show pictures. A macro sends `RESPOND TYPE=command MSG="action:prompt_image name [name ...]"` (4 names at most, small letters, digits and `-` only, never a path or an address) and Fluidd shows `img/wm/<name>.svg` from its own files at that place, side by side, one under the other on a narrow screen. The window is wider when it holds pictures. A Fluidd without this change ignores the line, and a picture that is missing is left out.
- The three pictures of the tool setter position helper ship with it: `setter-height`, `setter-place`, `setter-compare`.
- **Macro categories** (`scripts/wm_fluidd_categories.py`): `WM_SETTER_PROBE_POSITION` is in **RPI Calibration** as **Tool Setter Position**.

## 1.12.0

Endless spool: a tangle can start a swap too, a spare needs filament at the ACE, and the feed assist comes back after an ACE reconnect. Tested on a ZR Ultra-S with an ACE Pro (a tangle swap with the Fixed button). Goes with WM_Ultra_Vanilla_Klipper 2.13.0 (its `hub.cfg` tells the endless spool which toolhead tangled).

- **The hub sensors are tangle sensors.** 1.11.0 read `path_N` as "toolhead empty": when the ACE dropped off USB for a moment, the filament pulled tight, the tangle sensor fired and the endless spool swapped away from a toolhead that was not empty. `config/rpi_endless.cfg` no longer reads them as filament sensors: only the toolhead's own sensor says empty.
- **Swap on a tangle** (new switch, `WM_ENDLESS_SET TANGLE=1|0`, saved, default on). A spool whose end is fixed to the spool never frees the filament, so the toolhead sensor never sees "empty": only the tangle sensor notices it. With the switch on, a tangle on the printing toolhead starts a swap to an identical toolhead; with it off, or with no spare, the print stays paused. The toolhead that tangled is **out of the line** until `WM_ENDLESS_FIXED T=n` (the **Fixed** button under that toolhead, or in the window that opens at the swap), a reload of its filament, or the end of the print, so the printer does not swap back to it and tangle again.
- **A spare must have filament at the ACE too.** With an ACE Pro connected and in use, a toolhead whose ACE slot is empty is skipped, even with filament still in the toolhead. Without an ACE, with the ACE disconnected or switched off, only the toolhead sensors count: the endless spool works the same without an ACE.
- **Feed assist after an ACE reconnect (`config/rpi_ace.cfg`, `_WM_ACE_ASSIST_SYNC`).** When the ACE comes back from a USB drop it reports no feed assist; it is switched on again for the toolhead that is on the carriage (at most every 10 s). A toolhead the endless spool swapped away from stays off.
- **Fluidd panel rebuilt** (new zip, patch and checksum): the light "Hub" is called **Tangle**; "TANGLE OR SPOOL END" and a **Fixed** button under a toolhead that is out of the line; in the Endless spool section the ACE spools (filament or empty) left of the circle, the **Swap on a tangle** switch, and chips "tangle or spool end, check" and "spool empty at the ACE, refill".

## 1.11.0

Endless spool swaps by itself, for sets of 2, 3 or 4 identical toolheads. Tested on a ZR Ultra-S: one real runout and 10 swaps in one four-tool print, nozzle height after every swap within 0.02 mm. Goes with WM_Ultra_Vanilla_Klipper 2.12.0 (tool mapping reset at the end of a print, 20 mm purge in RESUME).

- **Automatic swap (`config/rpi_endless.cfg`).** New `_WM_ENDLESS_WATCH` / `_WM_ENDLESS_TICK`: every 3 s, a paused print with an empty toolhead on the carriage (its own sensor or its hub sensor) gets the next toolhead in number order with the same material and colour (`zr_tN_mat`, `zr_tN_color`) that has filament; after the last toolhead it starts again from the first. It runs on the printer, no browser needed. `WM_ENDLESS_SET AUTO=1|0` (saved as `wm_endless_auto`, default on) is the new **Swap automatically** switch; with it off the card offers the swap as before.
- **The swap itself is new.** Before, it first drove the empty, cold nozzle back onto the part, purged 20 mm wherever the toolhead stood after the tool change, and it had never run on a printer. Now: tool change from the park position, WonderMaker's `RESUME` does the only purge and wipe, and a last step (`_WM_ENDLESS_4`) moves the spare nozzle by the difference between the offsets of the two toolheads. Why that step: `RESTORE_GCODE_STATE` goes back to the machine position of the old toolhead and keeps the offsets of the new one (WonderMaker's Klipper, and upstream Klipper with `wm_gcode_compat`), which left the nozzle up to 0.16 mm too high or too low until the next layer.
- **No chain any more.** `WM_ENDLESS_CHAIN_SET`, the "If this spool runs out" field of the toolhead dialog and the saved `wm_endless_chainN` values are no longer used: identical material and colour decide. `WM_ENDLESS_PLAN` now shows the sets. The settings `variable_hop`, `variable_prime_mm` and `variable_prime_speed` are gone (nothing to tune).
- **Fluidd panel rebuilt** (new zip, patch and checksum): Endless spool section in the Toolheads card with a circle of the four toolheads in their filament colours and chips that say who takes over for whom, the Swap automatically switch, the chain field removed from the toolhead dialog.

## 1.10.0

Toolheads card additions, the feed assist fix, print time per toolhead and the new Fluidd category layout. Goes with WM_Ultra_Vanilla_Klipper 2.11.0 (the touchscreen line needs it on the screen board). Tested on a ZR Ultra-S.

- **Feed assist on the wrong slot (B-040, `config/rpi_ace.cfg`).** The 1 s watcher decided the feed assist with the values of the moment its timer fired; behind `START_PRINT` or a cancel its commands ran minutes later. Seen: assist on slot 1 while T0 printed, assist switched on for T0 after it was parked, then a 60 s ACE timeout and the ACE stuck "shifting" until it was switched off and on. The decision is now the new macro `_WM_ACE_ASSIST_SYNC`, which reads the printer when it runs, and the tool is the saved `current_extruder` (99 = none on the carriage). Tested: assist on slot 0 for a T0 print after T1 was parked, off after the cancel, no timeout.
- **Print time per toolhead (`config/rpi_stats.cfg`).** `_WM_STATS_TICK` adds the growth of `print_stats.print_duration` (pauses not counted) to the toolhead on the carriage and saves `wm_stat_time0` … `wm_stat_time3` about once a minute, at a tool change and at the end of a print. `WM_STATS_RESET` also zeroes them. The 2 s poll only calls the macro (same reason as B-040).
- **Fluidd categories (`scripts/wm_fluidd_categories.py`):** every category its own colour and one colour per category (installer colours are corrected, your own colours stay); WonderMaker's calibration in "WM Factory Calibration" (renamed from WM Ultra Calibration), every calibration macro of the Pi installer in "RPI Calibration" with readable names (Extruder Setup too), Unload Menu / Unload Stop in WM Ultra Filament, Nozzle Change and Chamber Light in ZR Tools, `SET_GCODE_OFFSET`, `Z_OFFSET_APPLY_*` and `WM_BED_SOAK` hidden, the empty Offset Calibration and Raspberry Pi categories removed. On an update each move happens once and only for entries left as the installer wrote them (README 3.5).
- **Fluidd panel rebuilt** (new zip, patch and checksum). Toolheads card:
  - **Unload Menu** button (`WM_UNLOAD_MENU`): a full-size blue button on its own line; locked only while a print runs or is paused (the macro refuses then).
  - Hub, Head and **Dock** lights for every toolhead, a little smaller (before: only with an ACE, without Dock); **Tool lock** and **Lock motor home** lights of the carriage.
  - **Print time per toolhead** next to the tool-change counts.
  - **Touchscreen line:** version, "update" chip when GitHub has a newer one, board CPU, KlipperScreen CPU, free memory, from `config/wm_screen_status.json` (uploaded by the board every minute), so it works also when the browser cannot reach the board.
- Tests: `tests/test_macros.py` is now part of `run_tests.sh` (counters, print time, feed assist); new category tests for the 1.9.x update path.

## 1.9.0

Faster ACE loads, the ACE window that closes by itself, and three switches plus friendly sensor names in Fluidd. Goes with WM_Ultra_Vanilla_Klipper 2.9.0 (live Z adjust per tool). Everything was tested on a ZR Ultra-S.

- **ACE load: fast part with the learned tube length (`config/rpi_ace.cfg`).** The hub sensors `path_N` always read on, so the old "fast until the hub sensor" never stopped at the hub: the load ran fast all the way by accident. Now the first load of a tool runs slow and measures the tube (saved `wm_ace_len_t0` … `wm_ace_len_t3`, T0 measured 1038 mm); later loads feed fast up to `slow_tail_mm` (60 mm) before the tool head, then slow until the toolhead sensor sees the filament. Only the toolhead sensor is read. `hub_to_head_mm` is now the longest slow feed (2000), `slow_timeout_s` 150. A load that reaches the tool head in the fast part measures again next time. Tested on T0 to T3.
- **Live Z adjust (`SET_GCODE_OFFSET` in `config/rpi_ace.cfg`).** When WM_Ultra_Vanilla_Klipper 2.9.0 is installed, a Z adjust is handed to its `_WM_LIVEZ_SGO`, which keeps one live adjust per tool. Without it nothing changes.
- **ACE "connection issue" window closes by itself (`extras/ace/manager.py`).** It closed only after about 3 minutes of stable connection. It now closes 10 s after every ACE is connected again; the issue stays marked until the connection is stable, so the window does not open again in that time. The driver sends `prompt_end` only while its own window is open (a `prompt_end` closes any window). Tested with a real unplug.
- **Cleanup (`config/rpi_ace.cfg`):** the unused `unload_tail` branch and `tail_mm` are gone, and the `ACE_WM_RETRACT` description is right. `WIPE_NOZZLE_SIMPLE` (removed from WonderMaker's files by WM_Ultra_Vanilla_Klipper 2.9.0) left the Fluidd macro category list.
- **Fluidd panel rebuilt** (new zip, patch and checksum):
  - Toolheads card: switches **ACE Pro**, **Bed warp wait** and **Nozzle heat growth**, each shown only when the printer has it. ACE Pro and Nozzle heat growth are locked while a print runs.
  - Filament Sensors card: friendly names (T<n> head filament, T<n> hub filament, T<n> in dock, Tool lock, Lock motor home) with the real Klipper name under each.
- Tests: the update test uses the new default of `hub_to_head_mm`.

## 1.8.0

ACE load and unload fixes from the printer, a smarter auto load, and a rebuilt Fluidd panel. Needs WM_Ultra_Vanilla_Klipper 2.8.0 for the chamber light button and the unload menu.

- **Unload and load use the real toolhead (`config/rpi_ace.cfg`).** `ACE_WM_LOAD`, `ACE_WM_UNLOAD`, `_WM_ACE_GRAB` and `_WM_ACE_UNLOAD_RUN` called `T<n>` and `M109 / M104 T<n>`, which follow the print map of the last print. With a map like "print tool 1 on toolhead 2" the unload of T1 went to toolhead 2. They now use `_CHANGE_TOOL T=n` and `SET_HEATER_TEMPERATURE`.
- **Unload no longer fails with "hub sensor never cleared".** The hub sensors `path_0` to `path_3` always read on, so they cannot tell when the filament is back. The end of an unload is now: toolhead sensor clear and the ACE slot empty or ready.
- **Auto load waits for the ACE and keeps the order.** A spool put in a slot goes into a queue. The load starts when the ACE has been quiet for 5 s (no slot preloading or shifting), spools load in the order they were put in, `ACE_WM_LOAD` queues itself while the ACE is preloading, and a feed the ACE refuses is tried again every 4 s, up to 10 times, with a console message.
- **A second spool is loaded after the first.** The hold after a load blocked every slot for 90 s. It now only holds the slot that was just loaded or unloaded (`hold_slot`).
- **Hold after an unload: 5 s instead of 90 s** (new `unload_hold` in `_WM_ACE`). Measured on the printer: after an unload the slot goes to empty and stays empty. A spool put back within the old 90 s was ignored for good, with no message. If the slot is ready when the 5 s end and the toolhead is empty, a window asks **Load T0** or **No** (`_WM_ACE_ASK_LOAD`, `_WM_ACE_ASK_YES`, `_WM_ACE_ASK_NO`); nothing loads without the click. The window was not tried on the printer yet, the 5 s hold was.
- **Works with the unload menu of the Pi installer** (`WM_UNLOAD_MENU`, `rpi_unload.cfg` in WM_Ultra_Vanilla_Klipper 2.8.0): `ACE_WM_STOP` also stops the menu's list and a failed ACE step ends it. Both calls are skipped when the menu is not installed.
- **Fluidd panel rebuilt** (new zip, patch and checksum):
  - Toolheads card: an ACE READY line under the toolhead status, bigger hub and head sensor dots, smaller dryer presets, a chamber target box with Set and Off, the Set, Off and Dry buttons at the same height.
  - **The CHAMBER LIGHT button switches the Moonraker power device `chamber_light`** instead of calling the screen board from the browser. Fluidd, the touchscreen and the macro `WM_CHAMBER_LIGHT` now always show the same state. The button is shown when Moonraker has that device (WM_Ultra_Vanilla_Klipper 2.8.0 writes it: `./installer.sh --light`). The old way (reading `rpi_chamber_light.json`) is removed from the panel.
- Tests: 9 new checks for the hold and the Load window in `tests/test_macros.py`, 2 new checks for the Fluidd zip.

## 1.7.10

- **New Fluidd macro category "Offset Calibration" (pink), second in the list after Raspberry Pi (`scripts/wm_fluidd_categories.py`).** It holds the tool offset and Z calibration macros of the Pi installer: `WM_FULL_OFFSET_CAL`, `WM_OFFSETS_ACCURATE`, `WM_OFFSETS_RAPID`, `WM_OFFSETS_Z_HOT`, `WM_NOZZLE_GROWTH_CAL`, `WM_NOZZLE_GROWTH`, `WM_Z_TRIM`, `WM_Z_TRIM_MENU`, `WM_PROBE_CALIBRATE`. The chamber light and unload macros (`WM_CHAMBER_LIGHT`, `WM_UNLOAD_MENU`, `WM_UNLOAD_STOP`) and `WM_FIRST_RUN_CAL` are in Raspberry Pi, blue, like the other `WM_*` macros. A new install gets this layout as it is.
- **Update from 1.7.9 or older:** the three offset macros that were in Raspberry Pi move to the new category once, and only while they are still as the installer put them. A macro you moved or recoloured stays, and one you move back is not moved again.
- A new category is now placed after the category that comes before it in the list, not at the end.
- **Fix: the runout pause of `path_0` and `filament0` was switched off after every Klipper start.** `rpi_ace_driver.cfg` named these two sensors for the driver, and the driver switches off the runout reaction of the sensors it is given. A runout at the hub then paused a print for T1 to T3 but not for T0. The driver (`extras/ace/config.py`, `extras/ace/manager.py`) now accepts having no toolhead sensor when `register_tool_commands: False`, and `config/rpi_ace_driver.cfg` no longer names any. Setups where the driver does the tool changes are not changed: the default sensor name `filament_runout_nozzle` still applies there. A sensor option written as `none` or left empty now also means no sensor.
- `config/rpi_ace_driver.cfg` and `config/rpi_ace.cfg`: the descriptions at the top now say what this setup is (ACE Pro as feeder and dryer, the printer keeps its own T0 to T3, the macros read the sensors themselves).
- **A short description next to every setting** in `config/rpi_ace_driver.cfg`, `config/rpi_ace.cfg`, `config/rpi_endless.cfg` and `config/rpi_stats.cfg` (40 added). Only comments changed, no value.
- An update replaces `rpi_ace_driver.cfg`, so the two old sensor lines go away by themselves. Restart the Klipper service after the update (a `RESTART` does not reload the driver).
- Tests: 10 new checks in `tests/test_fluidd_categories.py`.

## 1.7.9

- **OrcaSlicer plugin 0.7.2 (`orca_plugin/spool_toolhead_mapper.py`).** The `FILE=` part of `WM_SET_TOOL_MAP` / `ACE_SET_TOOL_MAP` now holds only the file name, not the full folder path Orca gives. Fluidd and the macro compare file names, so with a full path your "Choose toolheads" choice in Fluidd was always overwritten by Orca's map; now it is kept. The slicing step also writes lines to `~/.spool_toolhead_mapper.log` (started, skipped, what it wrote). 3 new tests.

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
