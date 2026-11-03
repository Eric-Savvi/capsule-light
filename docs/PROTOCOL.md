# NZXT Capsule Elite — USB lighting protocol

Unofficial notes on how the Capsule Elite's lighting is controlled over USB HID, as used by this app.
Every row marked *tested* was checked on a real mic (firmware `bcdDevice` 0x1005). Not affiliated with NZXT.

## Device

| | |
|---|---|
| USB | VID `0x1E71`, PID `0x260E`, interface 3 |
| HID collection | usage page `0xFFC0` (vendor), usage `0x01` |
| Report ID | `0xA8` — the only vendor report. Output 63 B + ID, input 31 B + ID |
| Other report | ID `0x03`, consumer page = the mute button (input only) |
| Driver | none needed; plain HID, works from user space on macOS |

## Packet format

```
host -> mic : [0xA8, cmd, payload…] zero-padded to 64 bytes (incl. report ID)
mic -> host : read:  [0xA8, cmd, data…]
              write: [0xA8, 0xFF, cmd, echo of payload…]   (0xFF = ACK)
```

Write command = read command − 1. Reads have an empty payload.

## Commands

| Setting | Write | Read | Payload | Tested |
|---|---|---|---|---|
| Front color (normal / unmuted) | `0x21` | `0x22` | 7 × RGB (21 B) | yes |
| Rear colors | `0x31` | `0x32` | 9 × RGB (27 B) | yes (shown only in effect 0) |
| Rear effect | `0x30` | `0x39` | 1 B effect code | yes |
| Effect speed | `0x35` | `0x36` | 1 B, 0–9 | ACKed |
| Effect brightness | `0x37` | `0x38` | 1 B, 0–100 | ACKed |
| Solid brightness | `0x2E` | `0x2F` | 1 B, 0–100 | ACKed |

CAM's write order for an effect: speed `0x35` → effect `0x30` → brightness `0x37`.
For Solid it sends colors → `0x2E`. The front only supports Solid in CAM.

### Rear effect codes (`0x30`)

| Code | Name (CAM) | Notes |
|---|---|---|
| 0 | Solid | **shows the 9 `0x31` colors.** Not offered by NZXT's app. Tested. |
| 1 | — | fixed white, ignores all colors. Tested. |
| 2 | RainbowWaveLeftToRight | factory default, animated rainbow. Tested. |
| 3 | RainbowWaveRadial | |
| 4 | ColorPulse | pulses fixed red, ignores colors. Tested. |
| 5 | CoveringMarquee | |
| 6 | ColorShift | |
| 7 | SolidGradient | still rainbow gradient, no speed. Tested. |
| 8 | CylonVisorRed | |
| 9 | CylonVisorMultiColor | |
| 10 | Disco | |

### Other commands seen (not needed, not sent)

- `0x01`, `0x03`, `0x05`, `0x07`: device start-up routine, empty payload (likely info reads).
- Firmware updates use separate commands that this project never sends. **Never touch the firmware.**

## Facts learned by testing

- Settings are **stored on the mic** and survive unplug/replug. No background agent needed.
- Mute → front shows red. That red is firmware-defined; no command found for it.
- Factory state (also in `capsule_backup.json`): front + rear colors `ffffff`, effect 2,
  speed 5, effect brightness 100, solid brightness 100.
- Colors are plain RGB byte order (byte-order swap ruled out).
- Tested from Swift on 2026-11-03:
  - `0x2E` ("solid brightness") dims **only the front**. `0x37` ("effect brightness") dims **only the rear**, in Solid (effect 0) as well as in effects.
  - Each write applies on its own: rear colors change in effect 0 without resending `0x30`, `0x37` and `0x35` change a running effect without resending it.
  - Black (`000000`) works as "off" for both zones (front via `0x21`, rear via `0x31` in effect 0).
- macOS: the HID interface's *primary* usage page is Consumer (`0x0C`, the mute button); `0xFFC0`
  is only in `DeviceUsagePairs`. Match with `kIOHIDDeviceUsagePageKey`, not `kIOHIDPrimaryUsagePageKey`.
  `IOHIDDeviceSetReport` takes the 64-byte buffer *including* `0xA8` as byte 0; input reports also start with `0xA8`.

## Safety rules (keep these)

1. Only send the write commands in the table above. Never send `0x01/03/05/07` or anything firmware-related.
2. Keep values in range (effect 0–10, speed 0–9, brightness 0–100).
3. Treat a missing `0xFF` ACK as an error and stop.
4. Offer "Restore factory" (the values above) in any UI.
