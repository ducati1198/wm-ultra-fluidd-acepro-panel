# Fluidd: WonderMaker Toolheads + ACE panel

> **⚠️ Use at your own risk.** Provided "as is", without warranty. See the [Disclaimer](../README.md#disclaimer-use-at-your-own-risk).

Fluidd v1.38.0 with:

- the WonderMaker **Toolheads** card (four toolheads, chamber with a target box, air filter, chamber light through the Moonraker power device `chamber_light`, doors, print with colours), and
- the **Choose toolheads** window at print start (filament mapping; opens every time you press Print), and
- the **ACE Pro** parts inside that same card: slot state and tangle/head sensor dots per toolhead, ACE header (connection, temperature, humidity), dryer with six material presets, endless-spool section (sets of identical toolheads, Swap automatically switch, swap offer), and an "ACE feeder · slot N" section in the toolhead dialog (Load, Unload, Feed assist, manual Feed/Retract, Stop).

- **pictures in a macro window** (`action:prompt_image name [name ...]`, files `img/wm/<name>.svg`; the tool setter position helper uses it).

There is no separate ACE card. The ACE parts appear only when Klipper reports `ace_instance_0`; the endless-spool row only when the macro `_WM_ENDLESS_CONTINUE` exists.

## Install the ready-made build

Use `./installer.sh`, or by hand:

1. `mv ~/fluidd ~/fluidd_backup`
2. `mkdir ~/fluidd && unzip fluidd-v1.38.0-zr-ace.zip -d ~/fluidd`
3. `cp ~/fluidd_backup/config.json ~/fluidd/` (if it exists)
4. Hard-refresh the browser (Cmd/Ctrl+Shift+R).

Check the download: `sha256sum -c fluidd-v1.38.0-zr-ace.zip.sha256`

## Build it yourself

```
git clone --branch v1.38.0 https://github.com/fluidd-core/fluidd
cd fluidd && git am --3way ../fluidd-v1.38.0-zr-ace.patch    # or: git apply
pnpm install --no-frozen-lockfile && pnpm run build           # output in dist/
```

The patch is a `git format-patch` series from v1.38.0: the WonderMaker ZR Toolheads commits, then "ACE feeder and dryer inside the Toolheads card", then "dryer presets and endless-spool offer", then "Choose toolheads window", and the later Toolheads card and window commits, the last one the purge window, the Resume tool and Load menu buttons and the hidden macro names, and the last one the filament colour lists, Color Picker and the name Black (33 in all).

What the card reads from Klipper: `ace_instance_0` (slots, dryer, temperature, humidity), `filament_switch_sensor path_N` and `filament<N>` (the dots), the save_variables value `wm_endless`, and the print file's metadata (colours and tools) to find a spare head. What it sends: `ACE_WM_LOAD`, `ACE_WM_UNLOAD`, `ACE_WM_STOP`, `ACE_ENABLE/DISABLE_FEED_ASSIST`, `ACE_FEED`, `ACE_RETRACT`, `ACE_START_DRYING`, `ACE_STOP_DRYING`, `_WM_ENDLESS_SET`, `_WM_ENDLESS_CONTINUE`, `_WM_ENDLESS_FIXED`, `_WM_PURGE`, `WM_PURGE_MENU`, `WM_LOAD_MENU`, `WM_UNLOAD_MENU`, `WM_RESUME_TOOL`.
