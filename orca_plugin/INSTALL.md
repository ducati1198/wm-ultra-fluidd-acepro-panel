# Spool and Toolhead Mapper: OrcaSlicer 2.5 plugin

> This one plugin works with both the WonderMaker ZR Ultra-S (toolheads, `WM_SET_TOOL_MAP`) and an ACE Pro printer such as a K1 (spools, `ACE_SET_TOOL_MAP`). It asks the printer (Moonraker) which one it is; for any other printer it writes nothing into the G-code. It uses the print host of each printer preset, so set that on every printer preset. Remove any older ACE Spool Mapper or WM Toolhead Mapper plugin first so the line is not written twice.

![Spools and Toolheads panel on a WonderMaker ZR Ultra-S](spool-toolhead-mapper-wm.png)

**What the panel does for you:** it refreshes by itself when you switch printer preset (a few seconds), it remembers your picks per printer between Orca sessions (they are dropped when a filament's colour or type changes), and it shows hints under a filament when two filaments use the same slot or toolhead, when the colour is clearly different, or (WonderMaker) when the chosen toolhead shows empty. Empty WonderMaker toolheads can be picked, with a warning; empty ACE slots stay blocked. Picks are saved in `~/.spool_toolhead_mapper.json` (if Orca does not allow writing it, they last for the session).


> Adapted from the ACE Spool Mapper plugin of [acepro-any-klipper](https://github.com/ducati1198/acepro-any-klipper). Use at your own risk (see the main README).

Pick which WonderMaker toolhead prints each OrcaSlicer filament, right in Orca. Works with **Upload and Print**,
**Upload** and **Export G-code**. It does the same job as the "Choose toolheads" window in Fluidd, but before the
file reaches the printer.

## Needs

- OrcaSlicer 2.5 or newer (plugin system).
- `wm_stats.cfg` on the printer (installed by `./installer.sh`; it holds the `WM_SET_TOOL_MAP` macro).
- The printer preset's host set to your printer (Printer settings → Connection), e.g. `192.168.0.50:7125`.

## Install (once)

1. In OrcaSlicer open **File → Plugins**.
2. **Browse plugins** (split button) → **Install local plugin** → pick `spool_toolhead_mapper.py`.
3. Orca asks once whether the plugin may connect to your printer: click **Yes**.
4. The plugin brings two parts: **Spools and Toolheads** (the panel) and **Spool and Toolhead Map** (the G-code step). Enable both.
5. Turn on the G-code step: switch Orca to **Advanced** mode, open your **Process** settings → **Others** →
   **Slicing Pipeline Plugin**, add **Spool and Toolhead Map**, save the process preset (for each process preset you print with).
6. Restart Orca. The **Spools and Toolheads** panel docks on the right of the 3D view.

## Use

1. In the panel, each project filament shows its best toolhead (**Auto →**: same material, closest colour, each
   toolhead once). Change any row to a specific toolhead or **As sliced**. The toolheads' colours and materials are
   the ones saved on the printer (the touchscreen / Fluidd Toolheads card); empty toolheads cannot be picked.
2. Slice and use **Upload and Print** (or Upload / Export). Sending never opens a window, so set the toolheads in
   the panel first.

The G-code gets two lines before the start G-code:

```
; Spool and Toolhead Mapper (wm): T0 as sliced, T1->Toolhead 4 PETG
WM_SET_TOOL_MAP MAP=0:0,1:3,2:2,3:3 FILE="benchy.gcode" KEEP_EXISTING=1
```

Print tool T1 is then printed with toolhead 4. Toolhead numbers in the macro start at 0.

## Good to know

- The whole map is written every time, so a map from an earlier print is never reused.
- If the panel has no data and the printer cannot be reached, the file prints as sliced (`0:0,1:1,2:2,3:3`).
- If you start the same file from Fluidd and choose toolheads in its "Choose toolheads" window, the Fluidd choice
  wins (`KEEP_EXISTING=1` and the saved `wm_map_file`).
- Orca's preview shows the G-code before the plugin step; the inserted lines are only in the sent file.
