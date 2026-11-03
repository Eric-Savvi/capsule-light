import AppKit
import SwiftUI

extension RGB {
    var color: Color { Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }

    init(_ color: Color) { self.init(NSColor(color)) }

    init(_ ns: NSColor) {
        let c = ns.usingColorSpace(.sRGB) ?? .white
        func byte(_ v: CGFloat) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }
        self.init(r: byte(c.redComponent), g: byte(c.greenComponent), b: byte(c.blueComponent))
    }

    var hex: String { String(format: "%02X%02X%02X", r, g, b) }
}

/// The mic's housing color. USB doesn't report it (same name and PID for both), so the user picks it.
enum MicFinish: String, CaseIterable, Codable, Identifiable {
    case black, white
    var id: Self { self }
    var name: String { rawValue.capitalized }
}

extension Lighting {
    /// Rear LED colors for drawing, from `rearLEDs(at:)` (shared with the 3D view).
    func rearColors(at time: Double?) -> [Color] { rearLEDs(at: time).map(Self.color) }
    var frontLEDColor: Color { Self.color(frontLED) }

    /// A still swatch for the effect, used on effect tiles and preset dots.
    func effectPreview(_ e: Effect) -> AnyShapeStyle {
        var l = self
        (l.effect, l.rearOn, l.rearBrightness) = (e, true, 100)
        return AnyShapeStyle(LinearGradient(colors: l.rearColors(at: nil), startPoint: .leading, endPoint: .trailing))
    }

    private static func color(_ c: SIMD3<Double>) -> Color { Color(.sRGB, red: c.x, green: c.y, blue: c.z) }
}

/// Flat front view of the Capsule Elite for small places (menu bar, widget): mesh, front light bar under it,
/// the 9 rear LEDs as a glow over the top edge. The main window uses `Mic3DView`.
struct MicGlyph: View {
    let lighting: Lighting
    var finish: MicFinish = .black
    var time: Double? = nil

    var body: some View {
        Canvas { ctx, size in
            let k = min(size.width / 100, size.height / 130)
            ctx.translateBy(x: (size.width - 100 * k) / 2, y: (size.height - 130 * k) / 2)
            ctx.scaleBy(x: k, y: k)
            let black = finish == .black
            let rear = lighting.rearColors(at: time)
            let ledX = (0..<9).map { 37 + Double($0) * 3.25 }

            // Rear LEDs light up the wall behind the top of the mic; a dark LED adds no glow.
            let glow = lighting.rearLEDs(at: time).map { c -> Color in
                let m = max(c.x, c.y, c.z)
                return m < 0.02 ? .clear : Color(.sRGB, red: c.x / m, green: c.y / m, blue: c.z / m).opacity(m)
            }
            ctx.drawLayer { g in
                g.addFilter(.blur(radius: 9))
                for (x, c) in zip(ledX, glow) {
                    g.fill(Circle().path(in: CGRect(x: x - 9, y: -2, width: 18, height: 22)), with: .color(c))
                }
            }

            // Stand: base plate and post.
            let metal = GraphicsContext.Shading.color(black ? Color(white: 0.16) : Color(white: 0.8))
            ctx.fill(Path(roundedRect: CGRect(x: 26, y: 118, width: 48, height: 6), cornerRadius: 2), with: metal)
            ctx.fill(Path(CGRect(x: 48, y: 96, width: 4, height: 23)), with: metal)

            // Body: upright rounded slab.
            let shell = black ? [Color(white: 0.22), Color(white: 0.09)] : [Color(white: 0.99), Color(white: 0.84)]
            ctx.fill(Path(roundedRect: CGRect(x: 31, y: 6, width: 38, height: 92), cornerRadius: 9),
                     with: .linearGradient(Gradient(colors: shell), startPoint: CGPoint(x: 31, y: 0), endPoint: CGPoint(x: 69, y: 0)))

            // Rear LED row peeking over the top edge.
            for (x, c) in zip(ledX, rear) {
                ctx.fill(Path(roundedRect: CGRect(x: x - 1.2, y: 6.2, width: 2.4, height: 1.4), cornerRadius: 0.7), with: .color(c))
            }

            // Front mesh grille.
            let mesh = CGRect(x: 34.5, y: 10, width: 31, height: 62)
            ctx.fill(Path(roundedRect: mesh, cornerRadius: 6), with: .color(black ? Color(white: 0.06) : Color(white: 0.72)))
            let hole = black ? Color.white.opacity(0.06) : Color.black.opacity(0.12)
            for y in stride(from: mesh.minY + 3, to: mesh.maxY - 2, by: 2.6) {
                for x in stride(from: mesh.minX + 3, to: mesh.maxX - 2, by: 2.6) {
                    ctx.fill(Circle().path(in: CGRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2)), with: .color(hole))
                }
            }

            // Front light bar (7 LEDs blend into one bar) under the mesh.
            let bar = CGRect(x: 38, y: 75, width: 24, height: 2.4)
            if lighting.frontOn {
                ctx.drawLayer { g in
                    g.addFilter(.blur(radius: 3))
                    g.fill(Path(roundedRect: bar.insetBy(dx: -2, dy: -2.5), cornerRadius: 3), with: .color(lighting.frontLEDColor))
                }
            }
            ctx.fill(Path(roundedRect: bar, cornerRadius: 1.2),
                     with: .color(lighting.frontOn ? lighting.frontLEDColor : Color.gray.opacity(0.3)))

            // Gain knob and logo.
            ctx.fill(Circle().path(in: CGRect(x: 36, y: 84, width: 7, height: 7)), with: .color(black ? Color(white: 0.3) : Color(white: 0.75)))
            ctx.fill(Path(roundedRect: CGRect(x: 51, y: 86.8, width: 12, height: 1.6), cornerRadius: 0.8),
                     with: .color(black ? Color.white.opacity(0.5) : Color.black.opacity(0.45)))
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let front = lighting.frontOn ? "front #\(lighting.frontColor.hex)" : "front off"
        let rear = !lighting.rearOn ? "rear off" : lighting.effect == .solid ? "rear #\(lighting.rearColor.hex)" : "rear \(lighting.effect.name)"
        return "Capsule, \(front), \(rear)"
    }
}

/// Green dot when the mic is connected.
struct ConnectionBadge: View {
    let connected: Bool

    var body: some View {
        Label {
            Text(connected ? "Connected" : "Not connected")
        } icon: {
            Circle().fill(connected ? Color.green : Color.secondary).frame(width: 7, height: 7)
                .shadow(color: connected ? .green : .clear, radius: 3)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(connected ? .primary : .secondary)
    }
}

/// Two small dots: a preset's front and rear look.
struct PresetDot: View {
    let lighting: Lighting

    var body: some View {
        HStack(spacing: -4) {
            Circle().fill(lighting.frontOn ? AnyShapeStyle(lighting.frontColor.color) : AnyShapeStyle(.gray.opacity(0.3)))
            Circle().fill(lighting.rearOn ? lighting.effectPreview(lighting.effect) : AnyShapeStyle(.gray.opacity(0.3)))
        }
        .frame(width: 18, height: 11)
        .overlay(Capsule().strokeBorder(.primary.opacity(0.1)))
    }
}
