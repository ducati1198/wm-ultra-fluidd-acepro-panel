<div align="center">

# WonderMaker ZR Ultra / Ultra-S: Fluidd Toolheads panel, for the ACE Pro or without it

**Use an Anycubic ACE Pro as the filament feeder and dryer of a WonderMaker ZR Ultra, and control it from the WonderMaker Toolheads card in Fluidd. No ACE Pro? The panel and the endless-spool option work without it.**
One installer, for WonderMaker's own Klipper / Moonraker / Fluidd.
With an ACE: one unit for T0–T3, slot N → hub inlet N → toolhead N.

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
| **Works without an ACE Pro** | Say no to the ACE question and you get the WonderMaker Toolheads panel and the endless-spool option only. Every ACE element stays hidden. Add the ACE later by running the installer again. |
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

What you need to run an ACE Pro on a WonderMaker ZR Ultra / Ultra-S, and how to connect it by USB. (The same guide is also in [`docs/HARDWARE.md`](docs/HARDWARE.md).) **No ACE Pro? Skip this section and go to [Install](#3-install).**

> The connector pinouts below come from the Kobra-S1/ACEPRO documentation and community adapter builds. They are not re-measured on every unit, so **check your adapter with a multimeter before plugging it in** (section 2.4).

### 2.1 What you need

| Part | Required | Notes |
|---|---|---|
| WonderMaker ZR Ultra or Ultra-S with WonderMaker's own Klipper, Moonraker and Fluidd | Yes | The installer looks for WonderMaker's `zru-s.cfg`, `_CHANGE_TOOL`, `UNLOAD_FILAMENT` and the hub sensor `path_0`, and refuses to run on anything else. |
| 1 Anycubic Color Engine Pro (first generation) | Only for the ACE parts | One unit covers all four toolheads (T0–T3). |
| USB cable or adapter for the ACE | Only for the ACE parts | Section 2.3 shows how to build one. |
| 4 PTFE tubes, ACE → filament hub | Only for the ACE parts | Slot 1 → hub inlet 1 → T0, slot 2 → inlet 2 → T1, slot 3 → inlet 3 → T2, slot 4 → inlet 4 → T3. |
| WonderMaker's hub sensors `path_0`…`path_3` and toolhead sensors `filament0`…`filament3` | Already on the printer | They stop the feed. No extra sensor is needed. No RDM sensor, encoder, cutter or poop basket is used. |
| USB port on the Klipper host | Only for the ACE parts | Use a powered hub if the ports are weak. |

The WonderMaker hub is passive (no motor). The ACE pushes and pulls the filament between the ACE and the hub; the toolhead extruder does the rest. The sensors are WonderMaker's own, set in its config; nothing about them is changed.

| Sensor | Where | Used for |
|---|---|---|
| `path_0` … `path_3` | WonderMaker filament hub (HUB MCU, pins `!HUB:PC13/PB12/PA2/PA3`) | The fast feed stops when the filament reaches the hub; during unload the ACE retracts until it clears. |
| `filament0` … `filament3` | Each toolhead | The slow feed stops when the filament reaches the toolhead; WonderMaker's own insert routine then takes over. |

### 2.2 Which ACE do you have?

| Unit | What the 4-pin connector carries | What to use |
|---|---|---|
| **ACE Pro** (first generation) | Native USB data | A plain USB-A adapter (below). It appears in Linux as `/dev/ttyACM*`. |
| **ACE 2 Pro** | RS-485, not USB | Not covered here. It needs the RS485-to-USB conversion cable from Anycubic's ACE 2 kit; a home-made USB cable will not work. |

The driver detects which protocol a unit speaks (`protocol: auto` in `wm_ace_driver.cfg`). The rest of this section is about the first-generation ACE Pro.

### 2.3 USB adapter for the ACE Pro

<div align="center">
<img src="docs/img/connection-chain.svg" alt="From the ACE Pro to a USB port" width="90%">
</div>

Only **three wires** are used: **D+, D- and GND**. Do **not** connect VBUS (5 V). The ACE has its own power supply, and a second 5 V source on the data cable can damage the host or the unit.

The stock cable has a 6-pin plug for the ACE's socket and a 4-pin plug that normally goes into an Anycubic printer. You can adapt either end:

| | Variant A: adapt the printer end | Variant B: adapt the ACE end |
|---|---|---|
| Original cable | Kept as it is | Not used |
| You build | A 4-pin socket to USB-A adapter | A 6-pin plug to USB-A cable |
| Donor part | A 4-pin ACE extension cable (cut one end off) | A 6-pin plug or pigtail |
| Good if | You want to keep the original cable and be able to go back to it | You want the shortest path or a tidy back cover |

<div align="center">
<img src="docs/img/connector-pinout.svg" alt="Connector faces" width="90%">
</div>

| ACE signal | USB-A pin |
|---|---|
| D+ | 3 |
| D- | 2 |
| GND | 4 |
| NC (not connected) | 1 (VBUS), left unconnected |

- The plug and the socket faces are mirror images of each other. That is normal for connectors that mate.
- Use the **position** in the diagram to find each pin. Wire colours differ between cable makers.
- The 6-pin plug has the same 2×2 signal block in two columns, plus a third column with no contacts.

### 2.4 Check before you plug in

With a multimeter (no ACE connected, nothing powered):

1. **Continuity:** D+ to USB pin 3, D- to USB pin 2, GND to USB pin 4.
2. **No shorts:** D+ to D-, D+ to GND and D- to GND must not beep.
3. **VBUS:** USB pin 1 must not be connected to anything on the ACE side.

Then plug it in, power the ACE and, on the machine that runs Klipper:

```bash
ls /dev/serial/by-id/          # the ACE should be listed
```

Restart Klipper and run `ACE_GET_STATUS`. The ACE chip in the Fluidd Toolheads card then shows "connected".

---

## 3. Install

### 3.1 Requirements

- WonderMaker's Klipper and Moonraker with its `zru-s.cfg` config, and Fluidd (optional, for the panel). Python 3.9 or newer in Klipper's environment (`~/klippy-env`), with `pyserial` for the ACE.
- **With an ACE:** one ACE Pro connected by USB (a powered hub is fine), and the tubes from section 2.1. **Without an ACE:** nothing else.
- No print running.
- SSH access to the machine that runs Klipper (user `t13dp`, default password in 3.2).
- The replacement main board does **not** have to be installed to run the installer. Klipper can stay stopped.

### 3.2 One-command installer

Log in to the printer's Klipper host over SSH first (Windows, macOS and Linux all have `ssh` in the terminal):

```bash
ssh t13dp@<printer-ip>        # user: t13dp   default password: TM88888
```

If you changed the password, use yours. Find `<printer-ip>` in your router's device list, or use the hostname if you know it. The first time, answer `yes` to the fingerprint question.

Then, on the printer:

```bash
sudo apt-get update
sudo apt-get install -y git
cd ~
git clone https://github.com/ducati1198/wm-ultra-fluidd-acepro-panel
cd wm-ultra-fluidd-acepro-panel
chmod +x installer.sh
./installer.sh --dry-run     # look first: shows the plan and changes nothing
./installer.sh
```

> **"destination path 'wm-ultra-fluidd-acepro-panel' already exists"?** You already downloaded it once. Do not clone again. Update the folder instead:
>
> ```bash
> cd ~/wm-ultra-fluidd-acepro-panel
> git pull
> ./installer.sh --update
> ```
>
> If `git pull` complains about local changes, see [section 9](#9-update-undo-and-uninstall).

The installer asks a few plain questions, shows exactly what it will change, and only then does it. It saves a backup first, so `./installer.sh --undo` puts everything back.

**The questions** (each has a one-line reason and a safe default):

1. Do you have an **Anycubic ACE Pro** to connect? (No gives you the panel and the endless-spool option only.)
2. With an ACE: load a spool **automatically** when you put it into a slot?
3. Add the experimental **endless-spool** macros? (Switched off until you turn them on in Fluidd.)
4. Install the **Fluidd panel**? (Your Fluidd folder is saved first.)

**What it does:**

1. Checks that this is a WonderMaker ZR Ultra config and that no print is running.
2. With an ACE: checks that the driver compiles and that `pyserial` is available, and looks for the ACE on USB (a warning, not a stop, if it is not there yet).
3. With an ACE: links the ACE driver (`extras/ace/`), `virtual_pins` and the ACE temperature sensor into Klipper's `extras` folder.
4. Copies the config files into your config folder and adds the `[include …]` lines to `printer.cfg`, right after `[include zru-s.cfg]` and above the SAVE_CONFIG block. No WonderMaker file is edited.
5. Installs the Fluidd panel if you chose it (your `config.json` is kept; the old folder is saved).
6. Saves everything it touched in `~/acepro-backup/wm-<date>`.
7. Asks once whether to restart Klipper (default no, and only if Klipper is running).
8. Prints your next steps.

**More commands:**

| Command | What it does |
|---|---|
| `./installer.sh --update` | Update the files. Your tuned values (distances, speeds) are kept. |
| `./installer.sh --check` | Look for problems. Changes nothing. |
| `./installer.sh --repair` | Restore the driver links and the include lines. |
| `./installer.sh --undo` | Put back the files saved before the last install. |
| `./installer.sh --uninstall` | Remove everything the installer added (saved first, so `--undo` brings it back). |
| `./installer.sh --dry-run` | Go through the questions and show what would change. Changes nothing. |

**Safety checks the installer makes first:**

- It **stops if a print is running or paused** (there is no override). `--check` and `--dry-run` still work.
- It **stops if the config is not a WonderMaker ZR Ultra / Ultra-S config.**
- It warns, and carries on, if it **sees no ACE on USB**.
- It **never flashes any board and never starts Klipper by itself.**

### 3.3 Check `printer.cfg`

The installer adds these for you (the two ACE lines only with an ACE, the endless line only if you chose it). Check they are there:

```ini
[include zru-s.cfg]
[include wm_ace_driver.cfg]
[include wm_ace.cfg]
[include wm_endless.cfg]
```

Restart Klipper from Fluidd (FIRMWARE_RESTART) or:

```bash
sudo systemctl restart klipper
```

With an ACE, run `ACE_GET_STATUS` in the console. You should see the unit connected with its four slots.

### 3.4 Fluidd panel

Installed by the installer (step 5 above). Manual steps and building it yourself: [`fluidd/README.md`](fluidd/README.md).

> **After any install or update, hard-refresh the browser** so Fluidd loads the new files:
> Windows/Linux `Ctrl+Shift+R` · macOS `Cmd+Shift+R`.

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

Written for the day the printer is running again. Do them in this order, empty bed, hand near the stop button. Steps 2–8 are for an ACE Pro; without one, only step 1 and step 9 apply.

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

**WonderMaker has no endless spool from the factory.** Their config, macros and the touchscreen app (v1.0.26) only pause on runout, and the product page says the same: "Printing pauses when filament runs out or breaks." This add-on is mine, built around WonderMaker's pause and resume. It is off by default and does not need an ACE Pro.

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
| Installer says "does not look like a WonderMaker ZR Ultra config" | Run it on the machine that has WonderMaker's `zru-s.cfg`, `_CHANGE_TOOL`, `UNLOAD_FILAMENT` and the `path_0` sensor. |
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
