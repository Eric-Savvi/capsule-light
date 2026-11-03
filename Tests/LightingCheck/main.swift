// Self-check for the Lighting <-> DeviceState mapping. Run:
//   swiftc Shared/CapsuleHID.swift Shared/Lighting.swift Tests/LightingCheck/main.swift -o /tmp/lc && /tmp/lc
import Foundation

let red = RGB(r: 255, g: 0, b: 0), blue = RGB(r: 0, g: 0, b: 255)
var l = Lighting()
(l.frontColor, l.rearColor, l.effect, l.speed, l.frontBrightness, l.rearBrightness) = (red, blue, .solid, 3, 40, 70)

// Round trip with both zones on.
precondition(Lighting(device: l.device, remembered: Lighting()) == l, "round trip")

// Front off: black on the mic, color remembered.
var off = l; off.frontOn = false
precondition(off.device.front == .black)
precondition(Lighting(device: off.device, remembered: l) == off, "front off keeps its color")

// Rear off: Solid black on the mic, effect and color remembered.
var rearOff = l; rearOff.effect = .disco; rearOff.rearOn = false
precondition(rearOff.device.effect == 0 && rearOff.device.rear == .black)
let back = Lighting(device: rearOff.device, remembered: rearOff)
precondition(!back.rearOn && back.effect == .disco && back.rearColor == blue, "rear off keeps its effect")

// All Off keeps settings; Factory matches the mic's factory state.
let dark = Preset.allOff.applied(to: l)
precondition(!dark.frontOn && !dark.rearOn && dark.frontColor == red && dark.effect == .solid)
precondition(Lighting.factory.device == DeviceState.factory, "factory")

// Values stay in range for the device.
var maxed = l; (maxed.speed, maxed.frontBrightness, maxed.rearBrightness) = (9, 100, 100)
precondition(maxed.device.speed == 9 && maxed.device.solidBrightness == 100)
print("LightingCheck: all passed")
