import Foundation
import Security

struct RGB: Codable, Hashable {
    var r: UInt8, g: UInt8, b: UInt8
    static let white = RGB(r: 255, g: 255, b: 255)
    static let black = RGB(r: 0, g: 0, b: 0)
    var bytes: [UInt8] { [r, g, b] }
}

/// Rear effect codes for command 0x30. Code 1 (fixed white) is left out on purpose.
enum Effect: UInt8, CaseIterable, Codable, Identifiable {
    case solid = 0, rainbowWave = 2, rainbowRadial = 3, colorPulse = 4, coveringMarquee = 5,
         colorShift = 6, solidGradient = 7, cylonRed = 8, cylonMulti = 9, disco = 10
    var id: UInt8 { rawValue }
    var usesSpeed: Bool { self != .solid && self != .solidGradient }
    var symbol: String {
        switch self {
        case .solid: "circle.fill"
        case .rainbowWave: "water.waves"
        case .rainbowRadial: "dot.radiowaves.left.and.right"
        case .colorPulse: "waveform.path"
        case .coveringMarquee: "chevron.forward.2"
        case .colorShift: "arrow.triangle.2.circlepath"
        case .solidGradient: "circle.lefthalf.filled"
        case .cylonRed: "eye.fill"
        case .cylonMulti: "arrow.left.and.right"
        case .disco: "sparkles"
        }
    }
    var name: String {
        switch self {
        case .solid: "Solid"
        case .rainbowWave: "Rainbow Wave"
        case .rainbowRadial: "Rainbow Radial"
        case .colorPulse: "Color Pulse"
        case .coveringMarquee: "Covering Marquee"
        case .colorShift: "Color Shift"
        case .solidGradient: "Solid Gradient"
        case .cylonRed: "Cylon Red"
        case .cylonMulti: "Cylon Multicolor"
        case .disco: "Disco"
        }
    }
}

/// What the mic itself stores, one value per command. Each zone uses one color for all LEDs.
struct DeviceState: Equatable {
    var front: RGB, rear: RGB
    var effect: UInt8, speed: UInt8, solidBrightness: UInt8, effectBrightness: UInt8

    static let factory = DeviceState(front: .white, rear: .white, effect: 2, speed: 5,
                                     solidBrightness: 100, effectBrightness: 100)

    init(front: RGB, rear: RGB, effect: UInt8, speed: UInt8, solidBrightness: UInt8, effectBrightness: UInt8) {
        (self.front, self.rear, self.effect, self.speed) = (front, rear, effect, speed)
        (self.solidBrightness, self.effectBrightness) = (solidBrightness, effectBrightness)
    }

    init(reading hid: CapsuleHID) throws {
        func color(_ cmd: UInt8) throws -> RGB {
            let d = try hid.read(cmd)
            return RGB(r: d[0], g: d[1], b: d[2]) // LED 0 stands for the zone
        }
        self.init(front: try color(0x22), rear: try color(0x32), effect: try hid.read(0x39)[0],
                  speed: try hid.read(0x36)[0], solidBrightness: try hid.read(0x2F)[0],
                  effectBrightness: try hid.read(0x38)[0])
    }

    /// Sends only what differs from `old` (everything if nil), in CAM's order:
    /// colors → solid brightness → speed → effect → effect brightness.
    /// Each command takes effect on its own (tested), so no resends are needed.
    func write(to hid: CapsuleHID, over old: DeviceState?) throws {
        // Safety rule 2: never send out-of-range values.
        precondition(effect <= 10 && effect != 1 && speed <= 9 && solidBrightness <= 100 && effectBrightness <= 100)
        if old?.front != front { try hid.write(0x21, Array([[UInt8]](repeating: front.bytes, count: 7).joined())) }
        if old?.rear != rear { try hid.write(0x31, Array([[UInt8]](repeating: rear.bytes, count: 9).joined())) }
        if old?.solidBrightness != solidBrightness { try hid.write(0x2E, [solidBrightness]) }
        if old?.speed != speed { try hid.write(0x35, [speed]) }
        if old?.effect != effect { try hid.write(0x30, [effect]) }
        if old?.effectBrightness != effectBrightness { try hid.write(0x37, [effectBrightness]) }
    }
}

/// What the user edits and what a preset stores. "Off" keeps the zone's settings so "on" brings them back.
struct Lighting: Codable, Equatable {
    var frontOn = true, frontColor = RGB.white, frontBrightness = 100.0
    var rearOn = true, rearColor = RGB.white, rearBrightness = 100.0
    var effect = Effect.rainbowWave, speed = 5.0

    static let factory = Lighting(device: .factory, remembered: Lighting())

    /// Off = the zone shows Solid black (tested: works for both zones).
    var device: DeviceState {
        DeviceState(front: frontOn ? frontColor : .black,
                    rear: rearOn ? rearColor : .black,
                    effect: rearOn ? effect.rawValue : Effect.solid.rawValue,
                    speed: UInt8(speed.rounded()),
                    solidBrightness: UInt8(frontBrightness.rounded()),
                    effectBrightness: UInt8(rearBrightness.rounded()))
    }

    /// Reads a zone that is black as "off" and takes its color/effect from `remembered`.
    init(device d: DeviceState, remembered: Lighting) {
        self = remembered
        frontOn = d.front != .black
        if frontOn { frontColor = d.front }
        rearOn = !(d.effect == Effect.solid.rawValue && d.rear == .black)
        if rearOn {
            rearColor = d.rear
            // shortcut: code 1 (fixed white, never set by this app) shows as Solid; fine unless set from elsewhere.
            effect = Effect(rawValue: d.effect) ?? .solid
        }
        speed = Double(d.speed)
        frontBrightness = Double(d.solidBrightness)
        rearBrightness = Double(d.effectBrightness)
    }

    init() {}
}

struct Preset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var lighting: Lighting

    // Built-ins. "All off" only switches both zones off and keeps their settings.
    static let factory = Preset(id: UUID(uuidString: "00000000-0000-0000-0000-00000000FAC7")!, name: "Factory", lighting: .factory)
    static let allOff = Preset(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!, name: "All Off", lighting: Lighting())
    var isBuiltIn: Bool { id == Self.factory.id || id == Self.allOff.id }

    func applied(to current: Lighting) -> Lighting {
        guard id == Self.allOff.id else { return lighting }
        var l = current
        (l.frontOn, l.rearOn) = (false, false)
        return l
    }
}

/// Storage shared by the app and the widget.
enum AppGroup {
    /// The App Group from our own entitlements, so it matches whatever team (or none) the app was signed with.
    static let id: String = {
        let task = SecTaskCreateFromSelf(nil)
        let groups = task.flatMap { SecTaskCopyValueForEntitlement($0, "com.apple.security.application-groups" as CFString, nil) } as? [String]
        guard let id = groups?.first else { fatalError("Missing com.apple.security.application-groups entitlement") }
        return id
    }()
    static let defaults = UserDefaults(suiteName: id)!

    static func load<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    static func save<T: Encodable>(_ value: T, as key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}

extension AppGroup {
    /// Darwin notification the widget posts after it wrote to the mic.
    static let changed = "\(id).changed" as CFString

    static func postChange() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(changed), nil, nil, true)
    }

    /// Calls `handler` on the main queue on every `postChange()`, from any process.
    static func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        changeHandler = handler
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { AppGroup.changeHandler?() } }
        }, changed, nil, .deliverImmediately)
    }

    nonisolated(unsafe) private static var changeHandler: (@MainActor () -> Void)?
}
