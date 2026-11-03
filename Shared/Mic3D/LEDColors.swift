import Foundation

/// LED colors for the 3D mic: 0…1 RGB with zone brightness and on/off already applied.
extension Lighting {
    var frontLED: SIMD3<Double> {
        frontOn ? Self.unit(frontColor) * frontBrightness / 100 : .zero
    }

    /// The 9 rear LEDs, left to right seen from behind. `time` nil = a still frame (Reduce Motion).
    /// shortcut: effects are approximations from CAM's names and a few looks at the mic; speeds are guessed, not measured.
    func rearLEDs(at time: Double?) -> [SIMD3<Double>] {
        guard rearOn else { return Array(repeating: .zero, count: 9) }
        let p = time.map { $0 * (0.15 + speed * 0.1) } ?? 0.5 // effect cycles elapsed
        let hue = { (h: Double) in Self.hue(h) }
        return (0..<9).map { i -> SIMD3<Double> in
            let x = Double(i) / 9
            let c: SIMD3<Double>
            switch effect {
            case .solid: c = Self.unit(rearColor)
            case .rainbowWave: c = hue(x - p)
            case .rainbowRadial: c = hue(abs(Double(i) - 4) / 9 - p)
            case .colorPulse: c = hue(floor(p) / 6) * (0.5 - 0.5 * cos(2 * .pi * p))
            case .coveringMarquee:
                let step = Int(floor(p * 9))
                c = hue(Double(i <= step % 9 ? step / 9 : step / 9 - 1) / 6)
            case .colorShift: c = hue(p / 3)
            case .solidGradient: c = hue(x * 0.75)
            case .cylonRed, .cylonMulti:
                let pos = 4 - 4 * cos(.pi * p) // sweeps 0…8 and back
                let tail = max(0, 1 - abs(Double(i) - pos) / 1.6)
                c = (effect == .cylonRed ? SIMD3(1, 0, 0) : hue(floor(p / 2) / 5)) * tail
            case .disco:
                let n = sin(Double(i) * 12.9898 + floor(p * 3) * 78.233) * 43758.5453
                c = hue(n - floor(n))
            }
            return c * rearBrightness / 100
        }
    }

    private static func unit(_ c: RGB) -> SIMD3<Double> { SIMD3(Double(c.r), Double(c.g), Double(c.b)) / 255 }

    /// Fully saturated color for hue 0…1 (wraps).
    private static func hue(_ h: Double) -> SIMD3<Double> {
        let h6 = (h - floor(h)) * 6
        func ch(_ k: Double) -> Double { min(max(abs((h6 + k).truncatingRemainder(dividingBy: 6) - 3) - 1, 0), 1) }
        return SIMD3(ch(0), ch(4), ch(2))
    }
}
