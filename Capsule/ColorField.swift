import AppKit
import SwiftUI

/// A short row of LED colors plus a custom-color swatch that opens a small popover right next to it.
/// No darkness control: each zone has its own brightness, and black means "off".
struct ColorField: View {
    @Binding var color: RGB
    @State private var editing = false

    private static let swatches: [(String, RGB)] = [
        ("White", .white), ("Red", RGB(r: 255, g: 20, b: 20)), ("Orange", RGB(r: 255, g: 110, b: 0)),
        ("Green", RGB(r: 0, g: 230, b: 80)), ("Cyan", RGB(r: 0, g: 210, b: 255)), ("Blue", RGB(r: 20, g: 70, b: 255)),
        ("Purple", RGB(r: 150, g: 40, b: 255)), ("Pink", RGB(r: 255, g: 30, b: 150)),
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Self.swatches, id: \.0) { name, swatch in
                Swatch(selected: swatch == color) { Circle().fill(swatch.color) } action: { color = swatch }
                    .accessibilityLabel(name)
            }
            let custom = !Self.swatches.contains { $0.1 == color }
            Swatch(selected: custom) {
                Circle().fill(custom ? AnyShapeStyle(color.color)
                                     : AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center)))
            } action: { editing = true }
            .accessibilityLabel("Custom color")
            .popover(isPresented: $editing, arrowEdge: .bottom) {
                CustomColor(color: $color).padding(16).frame(width: 260)
            }
        }
    }
}

private struct Swatch<Fill: View>: View {
    let selected: Bool
    @ViewBuilder var fill: Fill
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            fill
                .overlay(Circle().strokeBorder(.primary.opacity(0.12)))
                .padding(3)
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Hue and saturation as two thin tracks, plus a hex field.
private struct CustomColor: View {
    @Binding var color: RGB
    @State private var hue = 0.0
    @State private var saturation = 1.0
    @State private var hexText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Track(value: $hue, label: "Hue",
                  fill: LinearGradient(colors: stride(from: 0.0, through: 1, by: 1 / 12).map { Color(hue: $0, saturation: 1, brightness: 1) },
                                       startPoint: .leading, endPoint: .trailing))
            Track(value: $saturation, label: "Saturation",
                  fill: LinearGradient(colors: [.white, Color(hue: hue, saturation: 1, brightness: 1)], startPoint: .leading, endPoint: .trailing))
            HStack {
                Circle().fill(color.color).overlay(Circle().strokeBorder(.primary.opacity(0.12))).frame(width: 22, height: 22)
                Spacer()
                Text("Hex").foregroundStyle(.secondary)
                TextField("Hex", text: $hexText)
                    .font(.body.monospaced())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 84)
                    .onSubmit(applyHex)
                    .labelsHidden()
            }
        }
        .onAppear(perform: read)
        .onChange(of: hue) { write() }
        .onChange(of: saturation) { write() }
    }

    private func read() {
        let c = NSColor(srgbRed: Double(color.r) / 255, green: Double(color.g) / 255, blue: Double(color.b) / 255, alpha: 1)
        (hue, saturation, hexText) = (Double(c.hueComponent), Double(c.saturationComponent), color.hex)
    }

    private func write() {
        color = RGB(NSColor(colorSpace: .sRGB, hue: min(hue, 0.999), saturation: saturation, brightness: 1, alpha: 1))
        hexText = color.hex
    }

    private func applyHex() {
        let digits = hexText.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let v = UInt32(digits, radix: 16) else { hexText = color.hex; return }
        color = RGB(r: UInt8(v >> 16), g: UInt8((v >> 8) & 0xFF), b: UInt8(v & 0xFF))
        read()
    }
}

/// A thin capsule track with a knob; drag or click anywhere on it.
private struct Track<Fill: ShapeStyle>: View {
    @Binding var value: Double
    let label: String
    let fill: Fill

    var body: some View {
        GeometryReader { geo in
            let knob = 18.0
            ZStack(alignment: .leading) {
                Capsule().fill(fill).overlay(Capsule().strokeBorder(.primary.opacity(0.1))).frame(height: 10)
                Circle().fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .frame(width: knob, height: knob)
                    .offset(x: value * (geo.size.width - knob))
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                value = min(max((v.location.x - knob / 2) / (geo.size.width - knob), 0), 1)
            })
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { value = min(max(value + ($0 == .increment ? 0.05 : -0.05), 0), 1) }
    }
}
