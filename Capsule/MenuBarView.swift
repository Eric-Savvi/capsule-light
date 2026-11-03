import SwiftUI

struct MenuBarView: View {
    @Bindable private var store = Store.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                MicGlyph(lighting: store.lighting, finish: store.finish).frame(width: 36, height: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Capsule").font(.headline)
                    ConnectionBadge(connected: store.connected)
                }
                Spacer()
            }

            if store.connected {
                // Factory is left out here: it asks for confirmation in the main window.
                GlassEffectContainer {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(store.presets.filter { $0.id != Preset.factory.id }) { preset in
                            let button = Button { store.apply(preset) } label: {
                                Text(preset.name).lineLimit(1).frame(maxWidth: .infinity)
                            }
                            if store.currentPresetID == preset.id {
                                button.buttonStyle(.glassProminent)
                            } else {
                                button.buttonStyle(.glass)
                            }
                        }
                    }
                }
                ZoneRow(title: "Front", isOn: $store.lighting.frontOn, brightness: $store.lighting.frontBrightness)
                ZoneRow(title: "Rear", isOn: $store.lighting.rearOn, brightness: $store.lighting.rearBrightness)
            } else {
                Text("Plug in the mic to change its lighting.").foregroundStyle(.secondary)
            }

            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
            }

            Divider()
            Button("Open Capsule…") {
                openWindow(id: "main")
                NSApp.activate()
            }
            Button("Quit Capsule") { NSApp.terminate(nil) }
        }
        .buttonStyle(.plain)
        .padding(16)
        .frame(width: 300)
    }
}

private struct ZoneRow: View {
    let title: String
    @Binding var isOn: Bool
    @Binding var brightness: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: $isOn).toggleStyle(.switch)
            Slider(value: $brightness, in: 0...100) {
                Text("\(title) brightness")
            } minimumValueLabel: {
                Image(systemName: "sun.min")
            } maximumValueLabel: {
                Image(systemName: "sun.max")
            }
            .labelsHidden()
            .disabled(!isOn)
        }
    }
}
