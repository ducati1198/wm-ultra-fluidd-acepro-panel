<div align="center">

# ACE Pro on the WonderMaker ZR Ultra / Ultra-S

**Use an Anycubic ACE Pro as the filament feeder and dryer of a WonderMaker ZR Ultra, and control it from the WonderMaker Toolheads card in Fluidd.**
One installer. Runs on the Raspberry Pi with WonderMaker's own Klipper / Moonraker / Fluidd.
One ACE Pro for T0–T3: slot N → hub inlet N → toolhead N.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Python](https://img.shields.io/badge/Python-3.9+-blue.svg)](https://www.python.org/)
[![Fluidd](https://img.shields.io/badge/Fluidd-1.37.7%20Toolheads%20panel-orange.svg)](fluidd/)
[![Status](https://img.shields.io/badge/status-not%20yet%20tested%20on%20a%20printer-red.svg)](#6-first-tests-on-the-printer)

<img src="docs/img/fluidd-toolheads-ace-card.png" alt="WonderMaker Toolheads card with the ACE Pro in Fluidd" width="60%">

</div>

---

## Contents

0. [Disclaimer: use at your own risk](#disclaimer-use-at-your-own-risk)
1. [What you get](#1-what-you-get)
2. [Hardware and wiring](#2-hardware-and-wiring)
3. [Install](#3-install)
4. [Configure](#4-configure)
5. [Fluidd Toolheads + ACE panel](#5-fluidd-toolheads--ace-panel)
6. [First tests on the printer](#6-first-tests-on-the-printer)
7. [Everyday use and commands](#7-everyday-use-and-commands)
8. [Endless spool (experimental)](#8-endless-spool-experimental)
9. [Update, undo and uninstall](#9-update-undo-and-uninstall)
10. [Troubleshooting](#10-troubleshooting)
11. [Repository layout](#11-repository-layout)
12. [Credits and license](#12-credits-and-license)

---

## Disclaimer: use at your own risk

This project is provided **"as is"**, without warranty of any kind (see also the GPL v3 licence, sections 15 and 16).

- **Use it at your own risk.** You are responsible for what runs on your printer.
- **I am not responsible for any damage** to your printer, ACE Pro, electronics, hotend, prints or other property, or for any injury, fire or loss, caused by these files, the installer or the instructions.
- **This project has not been run on a real printer yet.** It was written against WonderMaker's configuration files and tested with a simulated printer (the installer, the Jinja in the macros, the Fluidd panel). The first run on hardware is yours. Section 6 lists what is still open.
- **Test in small steps**, with the printer empty, your hand near the emergency stop. Never leave a new setup unattended.
- Back up your config first. The installer makes backups and supports `--undo`, but you are responsible for keeping your own copies.
- This project is not made by or affiliated with WonderMaker, Anycubic or any other manufacturer. Product names belong to their owners.

> **No firmware is touched.** Nothing in this project flashes the main board, the toolhead boards or the hub board, and the installer never starts Klipper by itself.

---

## 1. What you get

| | |
|---|---|
| **ACE Pro as feeder** | `ACE_WM_LOAD T=n` feeds slot n to the hub inlet (fast), then to the toolhead sensor (slow). WonderMaker's own insert routine then heats and loads the filament. |
| **Uses WonderMaker's own sensors** | The hub sensor `path_N` stops the fast feed, the toolhead sensor `filament<N>` stops the slow feed. No new sensors needed. |
| **Unload** | `ACE_WM_UNLOAD T=n` runs WonderMaker's `UNLOAD_FILAMENT`, then the ACE pulls the filament back until `path_N` clears and into the ACE. |
| **Auto-load** | Put a spool into an ACE slot and it loads to the matching toolhead (switch off with `ACE_WM_AUTO ENABLE=0`). |
| **Feed assist** | Follows the active toolhead while printing. |
| **Dryer** | Start and stop from Fluidd, six material presets (PLA, PETG, ABS/ASA, TPU, Nylon/PA, PVA). Max 65 °C. |
| **One Fluidd card** | Everything sits in the WonderMaker **Toolheads** card, in the look of the ACE Pro card from [acepro-any-klipper](https://github.com/ducati1198/acepro-any-klipper). No separate ACE panel. |
| **Nothing replaced** | WonderMaker's `T0`…`T3`, `PAUSE`, `RESUME`, `LOAD_FILAMENT`, `UNLOAD_FILAMENT` stay as they are. The ACE driver is told not to create its own `T0`…`T7`. |
| **Endless spool (experimental)** | Off by default. When a head runs out the print pauses, and the card offers a spare head with the same colour and material. WonderMaker has no endless spool from the factory (section 8). |
| **Safe installer** | Asks plain questions, shows what changes, backs up first, `--undo`, `--check`, `--dry-run`, tests. |

<div align="center">
<img src="docs/img/fluidd-toolhead-dialog.png" alt="Toolhead dialog with the ACE feeder section" width="60%"><br>
<em>The toolhead dialog with the "ACE feeder · slot N" section (demo data).</em>
</div>

If no ACE is installed, the card looks exactly like the plain WonderMaker Toolheads card: every ACE element is hidden until Klipper reports an ACE (section 5).

---

## 2. Hardware and wiring

| Part | Required | Notes |
|---|---|---|
| WonderMaker ZR Ultra / Ultra-S running Klipper on a Raspberry Pi | Yes | Tested layout: Pi 400, Raspberry Pi OS Bookworm 64-bit, WonderMaker's Klipper and Moonraker fork. |
| 1 Anycubic ACE Pro | Yes | First generation (USB). One unit covers T0–T3. |
| USB adapter for the ACE | Yes | Data wires only (D+, D-, GND), never 5 V. See the [hardware guide](docs/HARDWARE.md). Check the adapter with a multimeter first. |
| 4 PTFE tubes, ACE → hub | Yes | Slot 1 → hub inlet 1 → T0, slot 2 → inlet 2 → T1, slot 3 → inlet 3 → T2, slot 4 → inlet 4 → T3. |

### Which sensors are used

| Sensor | Where | Used for |
|---|---|---|
| `path_0` … `path_3` | WonderMaker filament hub (HUB MCU, pins `!HUB:PC13/PB12/PA2/PA3`) | The fast feed stops when the filament reaches the hub; during unload, the ACE retracts until it clears. |
| `filament0` … `filament3` | Each toolhead | The slow feed stops when the filament reaches the toolhead; WonderMaker's own insert routine takes over. |

The hub is passive (no motor). The ACE does all the pushing and pulling between the ACE and the hub; the toolhead extruder does the rest.

---

## 3. Install

### 3.1 Requirements

- WonderMaker's Klipper, Moonraker and (optional) Fluidd on the Pi, with the `zru-s.cfg` config. The installer refuses to run on anything else.
- `python3`, `bash`, `git`; `unzip` is optional (Python is used if it is missing).
- Python 3.9 or newer in Klipper's environment (`~/klippy-env`), with `pyserial`.
- No print running.
- The replacement main board does **not** have to be installed to run the installer. Klipper can stay stopped.

### 3.2 One-command installer

On the Pi:

```
git clone https://github.com/ducati1198/wm-ultra-fluidd-acepro-panel ~/wm-ultra-fluidd-acepro-panel
cd ~/wm-ultra-fluidd-acepro-panel
./installer.sh --dry-run     # look first: shows the plan and changes nothing
./installer.sh               # install
```

It asks three questions (auto-load, endless-spool macros, Fluidd panel), shows a summary, and changes nothing until you confirm.

| Command | What it does |
|---|---|
| `./installer.sh` | Install. |
| `--dry-run` | Go through the questions and show the plan. Changes nothing. |
| `--update` | Update the files, keep your tuned values (distances, speeds). |
| `--check` | Report problems. Changes nothing. |
| `--repair` | Restore the driver links and the include lines. |
| `--undo [DIR]` | Put back the files saved before an install (default: the latest). |
| `--uninstall` | Remove everything the installer added (saved first). |

What the installer changes:

- Copies `wm_ace_driver.cfg`, `wm_ace.cfg` and (if you want it) `wm_endless.cfg` to `~/printer_data/config`.
- Adds three `[include …]` lines to `printer.cfg`, right after `[include zru-s.cfg]` (above the SAVE_CONFIG block). No WonderMaker file is edited.
- Links the ACE driver (`ace`, `virtual_pins.py`, `temperature_ace.py`) from this repository into `~/klipper/klippy/extras`.
- Optionally replaces `~/fluidd` with the panel build (your `config.json` is kept; the old folder is saved).
- Saves everything it touches in `~/acepro-backup/wm-<date>`.

What it does **not** do: flash any board, edit WonderMaker's macros, or start Klipper. At the end it asks once whether to restart Klipper (default no, and only if Klipper is running).

Keep the cloned folder: the driver is linked from it, so `git pull` plus `--update` is how you update.

### 3.3 Fluidd by hand (optional)

```
mv ~/fluidd ~/fluidd_backup
mkdir ~/fluidd && unzip fluidd/fluidd-v1.37.7-zr-ace.zip -d ~/fluidd
cp ~/fluidd_backup/config.json ~/fluidd/ 2>/dev/null
```

Check the download with `sha256sum -c fluidd-v1.37.7-zr-ace.zip.sha256`, then hard-refresh the browser. Details in [`fluidd/README.md`](fluidd/README.md).

---

## 4. Configure

Everything you may want to tune is at the top of `~/printer_data/config/wm_ace.cfg` (`[gcode_macro _WM_ACE]`). `--update` keeps your values.

| Variable | Default | Meaning |
|---|---|---|
| `variable_hub_to_head_mm` | 900 | Hub inlet → toolhead sensor. Limit of the slow phase. **Measure your tubes.** |
| `variable_max_total_mm` | 4000 | Absolute safety limit for one load. |
| `variable_tail_mm` | 1800 | Retract distance after the hub sensor clears (hub → inside the ACE). |
| `variable_fast_speed` / `slow_speed` | 60 / 20 mm/s | ACE → hub / hub → toolhead. |
| `variable_retract_speed` | 50 mm/s | Unload. |
| `variable_fast_timeout_s` / `slow_timeout_s` | 90 / 60 | A load that takes longer stops with an error. |
| `variable_auto` | 1 | 1 = load automatically when a spool is put into a slot. |

Driver settings (`wm_ace_driver.cfg`): `ace_count: 1`, `register_tool_commands: False` (keeps WonderMaker's own `T0`…`T3`), `feed_speed`, `retract_speed`, `max_dryer_temperature: 65`, `moonraker_lane_sync_enabled: False`.

Endless spool settings (`wm_endless.cfg`): `variable_hop` (Z lift while heads are swapped, 4 mm), `variable_prime_mm` (20), `variable_prime_speed` (300).

---

## 5. Fluidd Toolheads + ACE panel

The ACE has no card of its own. It lives inside the WonderMaker **Toolheads** card:

- **ACE header:** connection state, temperature and humidity.
- **Per toolhead:** ACE slot state (ready / empty / loading / assist) and two sensor dots (hub `path_N`, head `filament<N>`).
- **Dryer row:** target temperature, duration, Dry / Stop, and six presets.
- **Endless spool row:** a switch, plus a banner and one-tap confirmation when a head runs out.
- **Toolhead dialog → "ACE feeder · slot N":** Load from ACE, Unload to ACE, Feed assist on/off, manual Feed / Retract with length and speed, Stop motor.

Everything ACE-related is **hidden** when Klipper has no ACE object (`ace_instance_0`). The endless-spool row is hidden when the `WM_ENDLESS_CONTINUE` macro does not exist. So you can install the panel before the ACE hardware.

### Dryer presets

| Preset | Temperature | Time |
|---|---|---|
| PLA | 45 °C | 4 h |
| PETG | 55 °C | 6 h |
| ABS / ASA | 65 °C | 6 h |
| TPU | 50 °C | 6 h |
| Nylon / PA | 65 °C | 8 h |
| PVA | 45 °C | 6 h |

The ACE tops out at 65 °C. The presets only fill in the fields; you press **Dry**.

The panel is Fluidd v1.37.7 plus WonderMaker's ZR Toolheads card and the ACE parts. The source changes are in [`fluidd/fluidd-v1.37.7-zr-ace.patch`](fluidd/fluidd-v1.37.7-zr-ace.patch).

---

## 6. First tests on the printer

Written for the day the printer is running again. Do them in this order, empty bed, hand near the stop button.

1. `./installer.sh --check` → no problems. Restart Klipper once, read `~/printer_data/logs/klippy.log` for `[ace]` lines.
2. **Connection:** the ACE chip in the Toolheads card turns "connected". Temperature and humidity show.
3. **Dryer:** start the PLA preset for a few minutes, then Stop.
4. **Manual feed:** in the toolhead dialog, Feed 50 mm at speed 25, then Retract 50 mm. Check the direction and the Stop button.
5. **Sensor check:** push filament by hand to the hub and to the toolhead and watch the two dots.
6. **Measure the tubes** and set `variable_hub_to_head_mm` and `variable_tail_mm`.
7. `ACE_WM_LOAD T=0`, then `ACE_WM_UNLOAD T=0`, one head at a time.
8. Auto-load by inserting a spool, then feed assist during a short print.
9. Endless spool (section 8) only on a cheap print with you standing next to the printer.

### Still unverified (needs the printer)

- The driver starts with `ace_count: 1` and without the `acepro_macros.cfg` of acepro-any-klipper.
- `ACE_FEED` / `ACE_RETRACT` do not block, so the polling state machine can watch the sensors.
- The slot status field the panel reads (`ready` / `empty`).
- What the head sensor `docked<N>` means on the real hardware.
- Tube lengths, speeds and the overshoot after a sensor trips.
- `ACE_STOP_FEED` / `ACE_STOP_RETRACT` are harmless when the ACE is idle.
- The whole endless-spool sequence (tool change while paused, hop, prime).

---

## 7. Everyday use and commands

| Command | What it does |
|---|---|
| `ACE_WM_LOAD T=0..3` | Feed slot to hub and toolhead sensor; WonderMaker's insert routine finishes the load. |
| `ACE_WM_UNLOAD T=0..3` | `UNLOAD_FILAMENT`, then the ACE pulls the filament back. |
| `ACE_WM_RETRACT T=0..3` | Only the ACE part of an unload (after WonderMaker's `UNLOAD_FILAMENT`). |
| `ACE_WM_STOP` | Stop any feed or retract started by these macros. |
| `ACE_WM_AUTO ENABLE=1\|0` | Auto-load on spool insert. |
| `ACE_WM_DRY_START TEMP=55 DURATION=360` | Start drying (max 65 °C). |
| `ACE_WM_DRY_STOP` | Stop drying. |
| `ACE_FEED T= LENGTH= SPEED=` / `ACE_RETRACT …` | Manual moves (driver commands). |
| `ACE_ENABLE_FEED_ASSIST T=` / `ACE_DISABLE_FEED_ASSIST T=` | Feed assist on / off for one slot. |

Loads and unloads are refused while a print is running. Printing, colour mapping and tool changes stay exactly as WonderMaker made them.

---

## 8. Endless spool (experimental)

**WonderMaker has no endless spool from the factory.** Their config, macros and the touchscreen app (v1.0.26) only pause on runout, and the product page says the same: "Printing pauses when filament runs out or breaks." This add-on is mine, built around WonderMaker's pause and resume. It is off by default.

How it works:

1. A head runs out → WonderMaker pauses the print (its normal behaviour).
2. The Toolheads card looks for a spare head: loaded, same slot colour and material, not used by the running print.
3. You tap **Swap & continue** and confirm. The macro `WM_ENDLESS_CONTINUE FROM= TO=` restores the saved print state, lifts Z, changes head with WonderMaker's `_CHANGE_TOOL`, heats and primes the new head, wipes, moves back to the print position with the new head's offsets, and calls WonderMaker's `RESUME`.
4. If anything is not as expected, it stops and the print stays paused.

<div align="center">
<img src="docs/img/fluidd-endless-offer.png" alt="Endless spool offer in the Toolheads card" width="48%"> <img src="docs/img/fluidd-endless-confirm.png" alt="Confirmation dialog" width="48%"><br>
<em>The offer and the one-tap confirmation (demo data).</em>
</div>

Dry run: `WM_ENDLESS_PLAN FROM=0 TO=2` prints what a swap would do and moves nothing. Turn it on with the Fluidd switch or `WM_ENDLESS_SET ENABLE=1`.

**First use:** a cheap print, you at the printer, a hand on the stop button. The pieces are checked in simulation, but the real movement is untested.

---

## 9. Update, undo and uninstall

```
cd ~/wm-ultra-fluidd-acepro-panel && git pull
./installer.sh --update
```

`--update` keeps your tuned distances and speeds. Undo the last install or update with `./installer.sh --undo`. `--uninstall` removes the config files, the include lines and the driver links; WonderMaker's files are never touched. The Fluidd panel is put back by `--undo`.

---

## 10. Troubleshooting

| Problem | Try |
|---|---|
| Installer says "does not look like a WonderMaker ZR Ultra config" | Run it on the Pi that has `zru-s.cfg`, `_CHANGE_TOOL`, `UNLOAD_FILAMENT` and the `path_0` sensor. |
| `--check`: "linked driver is too old" | Update this repository (`git pull`), then run `--repair`. |
| `--check`: broken link | The repository was moved. Run `--repair` from its new place. |
| Klipper: "Unknown config object temperature_ace" or virtual pins | The links in `klippy/extras` are missing: `--repair`. |
| Klipper: T0..T3 behave differently | `register_tool_commands: False` is missing in `wm_ace_driver.cfg` (`--check` reports it). |
| No ACE parts in the Fluidd card | The ACE is not reported yet: restart Klipper, check the USB cable and the ACE power, hard-refresh the browser. |
| ACE not on USB | Data wires only (D+, D-, GND), no 5 V. Check the adapter with a multimeter. |
| Load stops with a timeout | Check `path_N` / `filament<N>` in the card, tube length, then raise the timeouts or `hub_to_head_mm`. |
| Fluidd update in Moonraker removed the panel | `./installer.sh --update`, answer yes to the Fluidd question. |

---

## 11. Repository layout

```
wm-ultra-fluidd-acepro-panel/
├── installer.sh                    Installer (install, --update, --check, --repair, --undo, --uninstall, --dry-run)
├── VERSION, CHANGELOG.md           Version and what changed
├── config/
│   ├── wm_ace_driver.cfg           Minimal [ace] driver config (no T0..T7, no cutter, no basket)
│   ├── wm_ace.cfg                  Load / unload / auto-load / feed assist / dryer macros
│   └── wm_endless.cfg              Experimental endless spool
├── extras/                         The ACE driver (linked into klippy/extras by the installer)
│   ├── ace/                        Driver from acepro-any-klipper + the register_tool_commands option
│   ├── virtual_pins.py
│   └── temperature_ace.py
├── fluidd/                         Fluidd 1.37.7 build + patch (Toolheads card with the ACE parts)
├── docs/                           Hardware notes, ACE USB adapter wiring, screenshots (demo data)
├── tests/run_tests.sh              Installer tests (fake home, no printer needed)
└── LICENSE                         GPL v3
```

The ACE driver in `extras/ace` is a copy of the one in [acepro-any-klipper](https://github.com/ducati1198/acepro-any-klipper) with one small addition: a `register_tool_commands` option (default `True`, so nothing changes elsewhere). The WonderMaker config sets it to `False`.

Run the tests: `bash tests/run_tests.sh`.

---

## 12. Credits and license

Built on:

- The ACE Pro driver and Fluidd work from [ducati1198/acepro-any-klipper](https://github.com/ducati1198/acepro-any-klipper), which builds on [Kobra-S1/ACEPRO](https://github.com/Kobra-S1/ACEPRO), [szkrisz/ACEPROSV08](https://github.com/szkrisz/ACEPROSV08), [utkabobr/DuckACE](https://github.com/utkabobr/DuckACE) and [agrloki/ValgACE](https://github.com/agrloki/ValgACE).
- [Fluidd](https://github.com/fluidd-core/fluidd) v1.37.7.
- WonderMaker's Klipper configuration for the ZR Ultra / Ultra-S (their files are read, never changed).

Config files and Fluidd panel by **ducati1198**.

**License:** GNU General Public License v3.0, see [`LICENSE`](LICENSE).
