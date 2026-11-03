"""Control NZXT Capsule Elite lighting from macOS.

  python capsule_light.py show                          # read everything (read-only)
  python capsule_light.py set front|rear RRGGBB [BRI]   # solid color, brightness 0-100 (default 100)
  python capsule_light.py effect rear NAME [SPEED] [BRI]  # NAME from EFFECTS, speed 0-9 (default 5)
  python capsule_light.py restore                       # write back the state saved before the first change

Protocol: docs/PROTOCOL.md. Every packet is [0xA8, cmd, payload…] padded to 64 bytes.
Only the documented lighting write commands are allowed; nothing firmware-related is ever sent.
"""
import json
import os
import sys

import hid
from capsule_read import PID, REPORT_ID, VID, query

# zone -> (color write cmd, color read cmd, LED count). The front only supports a solid color.
ZONES = {"front": (0x21, 0x22, 7), "rear": (0x31, 0x32, 9)}
# Effect name -> device effect code (cmd 0x30).
# "static": 1, tested: fixed white, ignores the 0x31/0x21 colors.
# Tested: solid-gradient (7) is a still rainbow gradient; color-pulse (4) pulses a fixed red.
# "solid": 0, tested: shows the 0x31 rear colors.
EFFECTS = {"solid": 0, "static": 1, "rainbow-wave": 2, "rainbow-radial": 3, "color-pulse": 4, "covering-marquee": 5,
           "color-shift": 6, "solid-gradient": 7, "cylon-red": 8, "cylon-multi": 9, "disco": 10}
NO_SPEED = {0, 1, 7}  # effects without a speed
SOLID_BRI, SPEED, EFFECT, EFFECT_BRI = 0x2E, 0x35, 0x30, 0x37
READS = {"solid_brightness": 0x2F, "speed": 0x36, "effect": 0x39, "effect_brightness": 0x38}
BACKUP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "capsule_backup.json")


def open_dev():
    path = next(d["path"] for d in hid.enumerate(VID, PID) if d["usage_page"] == 0xFFC0)
    dev = hid.device()
    dev.open_path(path)
    return dev


def send(dev, cmd, payload):
    assert cmd in (0x21, 0x31, SOLID_BRI, SPEED, EFFECT, EFFECT_BRI), f"refusing cmd {cmd:#x}"
    dev.write(bytes([REPORT_ID, cmd]) + payload + bytes(62 - len(payload)))
    r = dev.read(64, 500)
    if not (len(r) >= 3 and r[0] == REPORT_ID and r[1] == 0xFF and r[2] == cmd):
        raise SystemExit(f"cmd {cmd:#x} not acknowledged: {bytes(r).hex(' ')}")


def read_byte(dev, cmd):
    r = query(dev, cmd)
    if r is None:
        raise SystemExit(f"no reply to {cmd:#x}")
    return r[2]


def read_state(dev):
    state = {}
    for z, (_, rd, n) in ZONES.items():
        r = query(dev, rd)
        state[z] = [r[2 + 3 * i: 5 + 3 * i].hex() for i in range(n)]
    for k, cmd in READS.items():
        state[k] = read_byte(dev, cmd)
    return state


def set_colors(dev, zone, colors):
    wr, _, n = ZONES[zone]
    assert len(colors) == n
    send(dev, wr, b"".join(bytes.fromhex(c) for c in colors))


def set_effect(dev, code, speed, bri):
    assert code in EFFECTS.values() and 0 <= speed <= 9 and 0 <= bri <= 100
    if code not in NO_SPEED:
        send(dev, SPEED, bytes([speed]))
    send(dev, EFFECT, bytes([code]))
    send(dev, EFFECT_BRI, bytes([bri]))


def ensure_backup(dev):
    if not os.path.exists(BACKUP):
        with open(BACKUP, "w") as f:
            json.dump(read_state(dev), f, indent=1)
        print("saved backup to", BACKUP)


def main():
    args = sys.argv[1:] or ["show"]
    dev = open_dev()
    try:
        if args[0] == "show":
            print(json.dumps(read_state(dev), indent=1))
        elif args[0] == "set":
            zone, color = args[1], args[2].lower().lstrip("#")
            bri = int(args[3]) if len(args) > 3 else 100
            assert zone in ZONES and len(color) == 6 and int(color, 16) >= 0 and 0 <= bri <= 100
            ensure_backup(dev)
            set_colors(dev, zone, [color] * ZONES[zone][2])
            send(dev, SOLID_BRI, bytes([bri]))
            if zone == "rear":  # rear shows its colors only in effect 0 (tested)
                set_effect(dev, EFFECTS["solid"], 0, bri)
            print(json.dumps(read_state(dev), indent=1))
        elif args[0] == "effect":
            assert args[1] == "rear", "effects exist only on the rear"
            code = EFFECTS[args[2]]
            speed = int(args[3]) if len(args) > 3 else 5
            bri = int(args[4]) if len(args) > 4 else 100
            ensure_backup(dev)
            set_effect(dev, code, speed, bri)
            print(json.dumps(read_state(dev), indent=1))
        elif args[0] == "restore":
            with open(BACKUP) as f:
                s = json.load(f)
            for z in ZONES:
                set_colors(dev, z, s[z])
            send(dev, SOLID_BRI, bytes([s["solid_brightness"]]))
            set_effect(dev, s["effect"], s["speed"], s["effect_brightness"])  # effect last
            print(json.dumps(read_state(dev), indent=1))
        else:
            raise SystemExit(__doc__)
    finally:
        dev.close()


if __name__ == "__main__":
    main()
