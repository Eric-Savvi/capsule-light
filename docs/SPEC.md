# Capsule Light — macOS lighting control for the NZXT Capsule Elite

Protocol, command table and safety rules: `docs/PROTOCOL.md`. This file only says what the app does.

## Surfaces

- **Main window** — a normal app with a Dock icon while the window is open. Fixed size, Liquid Glass (`.glassEffect()`, macOS 26).
- **Menu-bar item** — always present; closing the window keeps the app running in the menu bar. No launch at login (the mic stores its settings itself).
- **Widget** — small (2 presets) and medium (4 presets): connection dot, mic drawing, your presets with "All Off" last (it becomes "Lights On" when everything is dark). Spike result: the sandboxed extension reaches the mic over HID, so buttons write directly and tell the app to reload (Darwin notification).

## Main window

- **Front**: on/off, one color for all 7 LEDs, brightness 0–100 (`0x2E`).
- **Rear**: on/off, mode picker (Solid = code 0, plus effects 2–10 by name; code 1 is hidden), color when Solid, speed (0–9) only for effects that use it (not Solid or Solid Gradient), brightness 0–100 (`0x37`).
- Brightness is per zone because the mic has it per zone (tested: `0x2E` = front only, `0x37` = rear only).
- **Sidebar**: presets (save current, rename, delete, reorder) and **Restore factory** at the bottom (asks for confirmation first).

## Menu-bar panel

Presets except Factory (one click applies; Factory needs the window's confirmation), front and rear on/off, front and rear brightness, "Open Capsule…", "Quit".

## Behavior

- **The mic is the source of truth**: the app reads its state on connect. Unplugged → "Capsule not connected", controls disabled, reconnects automatically.
- **Live apply, rate-limited**: at most one write per ~300 ms while dragging, plus a final write on release (the mic probably stores to flash).
- **Off** = that zone set to Solid black (`000000`). The app remembers the previous zone settings so "on" restores them. Mute still shows the firmware red.
- **Preset** = a named snapshot of everything (front color, rear mode/color, speed, brightness, both on/off states). Built-ins: "Factory" (from `capsule_backup.json`), "All off". Stored locally (an App Group, so the widget can read them).
- **Safety**: only the documented write commands, values in range, stop on a missing `0xFF` ACK, and say what will be sent before any write that hasn't been tested yet.

## Build

App "Capsule Light", bundle ID prefix from the `APP_ID_PREFIX` build setting, sandboxed with `com.apple.security.device.usb`, signed to run locally (any team works too). Built from source.

## Mic view

- **3D model** (`Shared/Mic3DView.swift`, SceneKit) in the window: current colors, effects animated, black/white finish (USB doesn't report it, so the user picks). Drag to rotate, click to flip; editing a zone turns it to that side.
- Menu bar and widget use a flat 2D drawing (`MicGlyph`) with the same LED colors.
