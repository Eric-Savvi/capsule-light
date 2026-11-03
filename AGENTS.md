# Instructions for coding agents

## Installing Capsule Light for a user

Goal: the app is in `/Applications/Capsule Light.app`, running, and talking to the user's NZXT Capsule Elite.
Run each step, check its result, and stop with a clear message if a check fails. Never use `sudo` yourself; give the user the command instead.

1. **Check the Mac.**
   - `sw_vers -productVersion` must be 26.0 or newer. If not: stop, the app needs macOS 26.
   - `xcodebuild -version` must work and show Xcode 26 or newer. If it fails or points to the Command Line Tools only, ask the user to install Xcode from the App Store, open it once, and run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` themselves.
   - Optional: `ioreg -p IOUSB -l -w0 | grep -c '"NZXT Capsule Elite"'` should print 1 or more. If 0, ask the user to plug the mic in (continuing without it is fine).
2. **Get the code.** `git clone https://github.com/Eric-Savvi/capsule-light.git` into a folder the user agrees to (default `~/Developer/capsule-light`), then `cd` into it. If it already exists, `git pull` instead.
3. **Build.**
   ```bash
   xcodebuild -project Capsule.xcodeproj -scheme Capsule -configuration Release -derivedDataPath build build
   ```
   It must end with `** BUILD SUCCEEDED **`. No signing setup is needed (the project signs to run locally).
4. **Install.** Quit a running copy first (`osascript -e 'quit app "Capsule Light"'`, ignore errors), then:
   ```bash
   ditto build/Build/Products/Release/Capsule.app "/Applications/Capsule Light.app"
   open "/Applications/Capsule Light.app"
   ```
5. **Tell the user** to:
   - click **Allow** when macOS asks whether Capsule Light may access data from other apps (first launch only);
   - add the widget if they want it: right-click the desktop → Edit Widgets… → search "Capsule".
6. **Verify.** A few seconds after launch, `ioreg -r -c IOHIDDevice -l | grep -c '"pid [0-9]*, Capsule"'` prints 1 when the app has the mic open. The window also shows a green "Connected".

If the widget is missing from the gallery, follow "Troubleshooting" in README.md.

## Changing the code

- Read `docs/PROTOCOL.md` first. Its safety rules are binding: send only the documented write commands (`0x21 0x31 0x2E 0x35 0x30 0x37`), keep values in range, stop on a missing `0xFF` ACK, and never send `0x01/03/05/07` or anything firmware-related. `Shared/CapsuleHID.swift` enforces this with preconditions; keep them.
- Before writing to the mic in a way that hasn't been tested, tell the user exactly what you will send.
- Build check: the `xcodebuild` line above. Logic check: `swiftc Shared/CapsuleHID.swift Shared/Lighting.swift Tests/LightingCheck/main.swift -o /tmp/lc && /tmp/lc`.
- Swift 5 language mode, SwiftUI, macOS 26 APIs (Liquid Glass). Files in `Shared/` are compiled into both the app and the widget.
