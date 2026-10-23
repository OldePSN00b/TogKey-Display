# TogKey Display

A floating Windows companion display for the **TogKey Pad Plus with Vial firmware**. It reads the pad's saved mappings, shows a six-button layout and encoder actions, and supports compact view and editable labels.

This is an independent community utility, not an official TogKey or Vial application.

## Start

1. Install [PowerShell 7 for Windows](https://learn.microsoft.com/powershell/scripting/install/install-powershell-on-windows) if it is not already installed.
2. Extract this folder to a writable location. Keep the included files together.
3. Connect the Pad Plus. **Unlock it in Vial before using automatic knob tracking**, following the instructions below. Then close Vial, including any Vial browser tab, without unplugging the pad.
4. Double-click **Start TogKey Display.cmd**.
5. Click **Pad 1**, **Pad 2**, **Pad 3**, or **Pad 4** to match the layer currently shown on the pad's OLED. The app waits for this selection instead of assuming the pad is on its first layer.

No administrator access, firmware changes, export file, or third-party HID package is required. The launcher starts PowerShell with a hidden console and a process-specific execution-policy bypass; it does not change the machine's execution-policy setting.

## Unlock the TogKey Pad Plus in Vial

**The Pad Plus must be unlocked for “Follow knob presses” to work.** Vial protects physical-switch monitoring while the keyboard is locked. Reading saved button mappings and selecting a layer manually can still work while it is locked. TogKey Display checks the unlock status but does not unlock the pad itself.

The display automatically checks the lock state while connected, even when knob tracking is off or the starting layer has not been selected. A **Pad locked · knob tracking unavailable** banner appears in both full and compact views. Click **How to unlock** for instructions in the GUI. The banner distinguishes unlocking in progress and disappears once an unlocked state is confirmed. A failed check is shown as an unknown/checking state, rather than assuming the pad is locked or unlocked.

1. **Close TogKey Display** so only Vial communicates with the pad during unlocking.
2. **Connect the Pad Plus by USB** and open the [Vial desktop application](https://get.vial.today/) or [Vial in a compatible browser](https://vial.rocks/). If the browser asks for a device, select the Pad Plus and allow the connection.
3. **Select the Pad Plus** in Vial's device list. Confirm that its key layout appears.
4. Open **Security → Unlock**. In the desktop application, **Ctrl+U** is the shortcut.
5. Vial opens an unlock prompt showing the physical keys to hold. For the Pad Plus firmware supported by this utility, these are the **upper-left and lower-left keys of the six main buttons**—the two buttons in the leftmost column, not the knob. If your Vial prompt highlights a different pair, use the keys it highlights.
6. **Press and hold both highlighted keys together** until Vial's progress bar finishes and the unlock dialog closes. Keep holding for the full countdown; releasing early can restart it. This is a physical key combination, regardless of the macros or actions assigned to those buttons.
7. **Close Vial or its browser tab. Leave the USB cable connected.** Do not select **Security → Lock**, because that disables switch monitoring again.
8. Start **TogKey Display**, select **Pad 1–4** to match the OLED, and enable **Follow knob presses**. If you are in compact view, uncheck **Compact** temporarily to access that option.

Unplugging the pad, resetting it, or losing USB power normally locks it again. Repeat these steps after reconnecting if the display asks you to unlock. Closing Vial alone does not relock the pad. Vial's unlock procedure and relocking behavior are described in its [security documentation](https://get.vial.today/docs/security.html).

If the display still asks you to unlock, close the display, reopen Vial and complete the countdown again, then close Vial and restart the display. Unlocking and choosing the current layer are separate steps: unlocking permits switch monitoring; selecting **Pad 1–4** synchronizes the estimated layer.

## Features

- Read mappings directly from the connected pad, automatically every eight seconds or immediately with **Read from pad**.
- Six tiles arranged like the physical buttons, plus encoder turn and press labels.
- Four layer selectors and optional estimated layer tracking from physical knob presses.
- **Compact** view, approximately 300 × 340 pixels.
- Drag the header to move the display; **Pinned** keeps it above other windows.
- Optional `.vil` import with **Open .vil**.

After editing in Vial, close Vial so the display can read the saved changes without competing HID traffic. A slow or failed read retains the previous labels and shows a connection message. The reader waits up to six seconds per request to accommodate macro execution, then retries automatically without clearing the selected layer. HID buffering is disabled so each transfer remains a single report.

### Editing mappings or macros in Vial

**Close TogKey Display completely before opening Vial.** This is the recommended workflow based on testing with the pad. Minimizing the window or turning off **Auto-read mappings** is not sufficient: lock checks and knob monitoring can still use the connection.

1. Close TogKey Display using its **×** button.
2. Open the Vial desktop application or browser version manually, select the Pad Plus, and unlock it if needed.
3. Make your mapping or macro changes. Close and reopen Vial to confirm that the new configuration persisted before relying on it.
4. Close Vial, including its browser tab, without unplugging the pad.
5. Start TogKey Display again. It reads the saved mappings directly from the pad.
6. Select **Pad 1–4** to match the OLED, then enable **Follow knob presses** if desired. Your saved custom labels are retained.

The pad's Raw HID protocol does not identify which application requested a reply. The display opens its live session exclusively, filters recognizable stale replies, and shows **Pad is in use** if another application already has the pad open. Close Vial and other display copies before retrying. Macro editing does not itself change the firmware's VIA protocol version.

## Label editing

Right-click a button tile, layer tab, or knob action to edit its display name. This also works in compact view. **Use automatic** removes an override.

Automatic labels use key names, website hostnames, application executable filenames, or a short preview of macro text. Macros containing only keypress actions show their macro number. Unknown keycodes appear as hexadecimal values. There are no app-specific name rules or predefined personal layer names.

Custom button and knob labels belong to a position on a particular layer. They survive mapping refreshes and continue to apply even if that position is assigned a different action, until reset. Layer selection, label editing, and tile clicks do not change the pad or execute its macros.

Names are saved in **TogKey labels.json** beside the script. Keep this file when upgrading. Do not include it in a public release unless you intend to share those names; `.gitignore` excludes it. No label file or personal export is included in this package.

Older releases may have created **TogKey settings.json** for the Vial launcher. This version does not read or update that legacy file; it is still excluded from Git.

## Active layer and knob tracking

The supported firmware does **not** expose a direct active-layer query. On each launch, the display shows **Sync needed** and waits for you to select the layer that matches the pad's OLED. Button labels remain hidden until that selection. An actual disconnected pad requires a fresh selection after reconnecting; a temporary timeout or protocol retry does not clear synchronization.

The display uses the OLED's **1–4** numbering. These correspond to **Vial layers 0–3**. Existing saved custom-label keys still use the Vial indices and remain compatible.

To follow physical knob presses, enable **Follow knob presses** and select the current layer once to synchronize. Switch tracking waits until that selection. The display then advances when it observes a knob press, provided the knob is assigned `TOG_LAY` / `USER00` on the displayed layer. Clicking a layer again explicitly resynchronizes and discards older queued press events.

This is an estimate. Fast taps, reconnects, mapping-read pauses, or other layer-changing keys can cause drift. Select the matching layer again to resynchronize. Compact view leaves tracking and auto-read running.

Switch monitoring requires an unlocked pad. Follow [Unlock the TogKey Pad Plus in Vial](#unlock-the-togkey-pad-plus-in-vial), then close Vial without unplugging the pad. This utility reads the unlock status but never unlocks the device itself.

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
