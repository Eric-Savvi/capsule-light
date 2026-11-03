// Debug renderer for Shared/Mic3DView.swift: writes PNGs of the 3D mic and self-checks the LED colors.
// Run from the repo root:
//   swiftc -Onone Shared/Lighting.swift Shared/CapsuleHID.swift Shared/Mic3D/*.swift Shared/Mic3DView.swift docs/mic3d-render/main.swift -o build/mic3d-render
//   build/mic3d-render build/mic3d
import AppKit
import SceneKit

// LED color self-checks.
var l = Lighting()
l.effect = .solid
l.rearColor = RGB(r: 255, g: 0, b: 0)
l.rearBrightness = 50
assert(l.rearLEDs(at: 3) == Array(repeating: SIMD3(0.5, 0, 0), count: 9))
l.rearOn = false
l.frontOn = false
assert(l.rearLEDs(at: 3).allSatisfy { $0 == .zero } && l.frontLED == .zero)
for effect in Effect.allCases {
    l = Lighting()
    l.effect = effect
    for t in stride(from: 0.0, to: 20, by: 0.37) {
        assert(l.rearLEDs(at: t).count == 9 && l.rearLEDs(at: t).allSatisfy { ($0.min() >= 0) && ($0.max() <= 1) }, "\(effect)")
    }
}

// Motion self-checks: springs settle on target without overshoot, flips and momentum land where expected.
func settle(_ m: inout Motion, from t0: Double = 0) -> [Double] {
    (1...300).map { i -> Double in m.step(to: t0 + Double(i) / 60, snap: false); return m.yaw! }
}
var m = Motion()
m.step(to: 0, snap: false)
assert(m.yaw == MicModel.yaw(for: .front))
m.show(.rear)
var path = settle(&m)
assert(abs(path.last! - MicModel.yaw(for: .rear)) < 1e-3 && zip(path, path.dropFirst()).allSatisfy { $0 <= $1 + 1e-12 })
m.flip()
assert(abs(m.yawTarget - (MicModel.yaw(for: .rear) + .pi)) < 1e-9)
path = settle(&m, from: 5)
m.drag(by: CGVector(dx: 10, dy: 0), ended: nil, momentum: true)
let released = m.yaw!
m.drag(by: .zero, ended: CGVector(dx: 600, dy: 0), momentum: true)
path = settle(&m, from: 10)
assert(abs(path.last! - (released + 600 * Motion.radiansPerPoint / Motion.omega)) < 1e-3)
assert(zip(path, path.dropFirst()).allSatisfy { $1 >= $0 - 1e-12 }, "momentum overshoots")
m.drag(by: CGVector(dx: 0, dy: -1000), ended: .zero, momentum: true)
assert(m.pitch == Motion.pitchLimit)

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/mic3d")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)

func render(_ name: String, _ look: MicLook, time: TimeInterval = 1.3, turn: Double = 0, backdrop: NSColor? = NSColor(white: 0.5, alpha: 1)) throws {
    let model = MicModel()
    model.look = look
    model.update(at: time)
    model.drag(by: CGVector(dx: turn / Motion.radiansPerPoint, dy: 0), ended: .zero)
    model.update(at: time)
    renderer.scene = model.scene
    renderer.pointOfView = model.camera
    let size = CGSize(width: 600, height: 800)
    let image = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
    let final = NSImage(size: size, flipped: false) { rect in
        if let backdrop { backdrop.setFill(); rect.fill() }
        image.draw(in: rect)
        return true
    }
    try png(final, name)
    sheet.append(final)
}

func png(_ image: NSImage, _ name: String) throws {
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name + ".png"))
}
var sheet: [NSImage] = []

var look = MicLook()
look.lighting.frontColor = RGB(r: 0, g: 190, b: 255)
for (finish, white) in [("black", false), ("white", true)] {
    look.whiteFinish = white
    for (side, focus) in [("front", MicFocus.front), ("rear", .rear)] {
        look.focus = focus
        try render("\(finish)-\(side)", look)
    }
}
try render("white-side", look, turn: 0.45 + .pi / 2, backdrop: NSColor(white: 0.8, alpha: 1)) // like photo 4
look.whiteFinish = false
look.focus = .rear
try render("black-rear-alpha", look, backdrop: nil)
look.lighting.rearOn = false
look.lighting.frontOn = false
try render("black-rear-off", look)
// All renders side by side.
try png(NSImage(size: CGSize(width: 300 * sheet.count, height: 400), flipped: false) { _ in
    for (i, image) in sheet.enumerated() { image.draw(in: CGRect(x: 300 * i, y: 0, width: 300, height: 400)) }
    return true
}, "sheet")
print("wrote \(out.path)")
