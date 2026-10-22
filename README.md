# TogKey Display

A floating Windows companion display for the **TogKey Pad Plus with Vial firmware**. It reads the pad's saved mappings, shows a six-button layout and encoder actions, and supports compact view and editable labels.

This is an independent community utility, not an official TogKey or Vial application.

## Start

1. Install [PowerShell 7 for Windows](https://learn.microsoft.com/powershell/scripting/install/install-powershell-on-windows) if it is not already installed.
2. Extract this folder to a writable location. Keep the included files together.
3. Connect the Pad Plus and close Vial, including any Vial browser tab.
4. Double-click **Start TogKey Display.cmd**.

No administrator access, firmware changes, export file, or third-party HID package is required. The launcher starts PowerShell with a hidden console and a process-specific execution-policy bypass; it does not change the machine's execution-policy setting.

## Features

- Read mappings directly from the connected pad, automatically every eight seconds or immediately with **Read from pad**.
- Six tiles arranged like the physical buttons, plus encoder turn and press labels.
- Four layer selectors and optional estimated layer tracking from physical knob presses.
- **Compact** view, approximately 300 × 340 pixels.
- Drag the header to move the display; **Pinned** keeps it above other windows.
- Optional `.vil` import with **Open .vil**.

After editing in Vial, close Vial so the display can read the saved changes without competing HID traffic. A failed read retains the previous labels and shows a connection message.

## Label editing

Right-click a button tile, layer tab, or knob action to edit its display name. This also works in compact view. **Use automatic** removes an override.

Automatic labels use key names, website hostnames, application executable filenames, or a short preview of macro text. Macros containing only keypress actions show their macro number. Unknown keycodes appear as hexadecimal values. There are no app-specific name rules or predefined personal layer names.

Custom button and knob labels belong to a position on a particular layer. They survive mapping refreshes and continue to apply even if that position is assigned a different action, until reset. Layer selection, label editing, and tile clicks do not change the pad or execute its macros.

Names are saved in **TogKey labels.json** beside the script. Keep this file when upgrading. Do not include it in a public release unless you intend to share those names; `.gitignore` excludes it. No label file or personal export is included in this package.

## Active layer and knob tracking

The supported firmware does **not** expose a direct active-layer query. Select the layer that matches the pad's OLED.

To follow physical knob presses, enable **Follow knob presses** and select the current layer once to synchronize. The display then advances when it observes a knob press, provided the knob is assigned `TOG_LAY` / `USER00` on the displayed layer.

This is an estimate. Fast taps, reconnects, mapping-read pauses, or other layer-changing keys can cause drift. Select the matching layer again to resynchronize. Compact view leaves tracking and auto-read running.

Switch monitoring requires an unlocked pad. If prompted, unlock through Vial's Security menu, then close Vial. This utility reads the unlock status but never unlocks the device itself.

## Supported hardware

Currently targets this specific Pad Plus layout and firmware identity:

| Setting | Expected value |
| --- | --- |
| USB VID / PID | `FEED` / `8687` |
| Raw HID usage page / usage | `FF60` / `61` |
| Vial keyboard UID | `77 F7 14 BB 74 32 66 E9` |
| Protocols | VIA 9, Vial 6 |
| Matrix / layers / encoder | 3 × 3 / 4 / 1 |

Other TogKey models and firmware identities are not supported by this release. Only one matching pad may be connected. Transparent assignments are resolved against default layer 0, matching the supported firmware's layer-cycling behavior. This display shows mapped keycodes and macro text; it does not simulate tap dance, combos, or key overrides.

## Files

- `TogKey Display.ps1`: WPF interface, labels, and configuration import.
- `TogKey Hid.cs`: Windows HID access and read-only protocol client, compiled in memory at startup.
- `Start TogKey Display.cmd`: double-click launcher.
- `LICENSE`: MIT license for this utility.

The HID client permits only the read commands it uses. It does not write mappings, change firmware, reset memory, send keyboard input, or change the unlock state. No network connection is used by the utility.

## Command-line options

Run from this folder:

```powershell
pwsh -NoProfile -STA -File '.\TogKey Display.ps1' -Compact
pwsh -NoProfile -STA -File '.\TogKey Display.ps1' -VialPath 'C:\Path\To\layout.vil'
pwsh -NoProfile -STA -File '.\TogKey Display.ps1' -LabelsPath 'C:\Path\To\labels.json'
pwsh -NoProfile -STA -File '.\TogKey Display.ps1' -ReadPadOnly
```

`-ReadPadOnly` prints a mapping snapshot and exits. Macro entries in that diagnostic snapshot contain only text segments, not the original action sequence; it is not a Vial backup. It may contain the connected pad's macro text, so review it before sharing.

`-VialPath` optionally displays an export while connecting. Selecting **Open .vil** in the interface pauses direct reads. **Read from pad** reconnects; enable **Auto-read mappings** to resume periodic refresh.

## Protocol references

This utility implements a subset of the documented/public VIA and Vial wire behavior. It does not bundle the firmware or Vial GUI.

- [Vial/QMK VIA command handling](https://github.com/vial-kb/vial-qmk/blob/vial/quantum/via.c)
- [Vial command handling](https://github.com/vial-kb/vial-qmk/blob/vial/quantum/vial.c)
- [Vial macro protocol](https://github.com/vial-kb/vial-gui/blob/master/src/main/python/protocol/macro.py)
- [Microsoft HID reports](https://learn.microsoft.com/windows-hardware/drivers/hid/obtaining-hid-reports)
