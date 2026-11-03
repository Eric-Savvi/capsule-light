"""Read-only probe for the NZXT Capsule Elite (USB 1e71:260e) on macOS.

Sends only the six read commands from docs/PROTOCOL.md (all with an empty payload)
and prints the raw replies. Never writes settings.
Needs: pip install hidapi
"""
import time
import hid

VID, PID = 0x1E71, 0x260E
REPORT_ID = 0xA8
# Read commands; 0x22 = front colors, 0x32 = rear colors.
READ_ONLY = (0x22, 0x2F, 0x32, 0x36, 0x38, 0x39)


def query(dev, cmd):
    assert cmd in READ_ONLY, f"refusing to send non-read command {cmd:#x}"
    dev.write(bytes([REPORT_ID, cmd]) + bytes(62))  # 64-byte output report incl. report ID
    deadline = time.time() + 1.0
    while time.time() < deadline:
        r = dev.read(64, 200)
        if len(r) >= 2 and r[0] == REPORT_ID and r[1] == cmd:
            return bytes(r)
    return None


def main():
    path = next(d["path"] for d in hid.enumerate(VID, PID) if d["usage_page"] == 0xFFC0)
    dev = hid.device()
    dev.open_path(path)
    try:
        for cmd in READ_ONLY:
            r = query(dev, cmd)
            print(f"{cmd:#04x}:", r.hex(" ") if r else "no reply")
    finally:
        dev.close()


if __name__ == "__main__":
    main()
