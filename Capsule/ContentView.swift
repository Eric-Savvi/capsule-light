import SwiftUI

struct ContentView: View {
    @Bindable private var store = Store.shared
    @State private var confirmFactory = false
    @State private var naming: NameRequest?
    @State private var deleting: Preset?
    @State private var focus = MicFocus.front

    /// One alert for both "Save as Preset" (no preset yet) and "Rename".
    struct NameRequest: Identifiable {
        var id: UUID? { preset?.id }
        var preset: Preset?
        var name: String
    }

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(200)
        } detail: {
            detail
        }
        .frame(width: 940, height: 640)
        .confirmationDialog("Restore factory lighting?", isPresented: $confirmFactory) {
            Button("Restore Factory", role: .destructive) { store.apply(.factory) }
        } message: {
            Text("Front and rear go back to white, the rear runs Rainbow Wave, and brightness goes to 100.")
        }
        .alert(naming?.preset == nil ? "New Preset" : "Rename Preset",
               isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: Binding(get: { naming?.name ?? "" }, set: { naming?.name = $0 }))
            Button("Save") { saveName() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \u{201C}\(deleting?.name ?? "")\u{201D}?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Preset", role: .destructive) {
                if let id = deleting?.id { store.userPresets.removeAll { $0.id == id } }
            }
        } message: {
            Text("The mic keeps its current lighting.")
        }
    }

    // MARK: sidebar

    private var sidebar: some View {
        List(selection: Binding(get: { store.currentPresetID }, set: select)) {
            Section("Built-in") {
                Label("All Off", systemImage: "lightswitch.off").tag(Preset.allOff.id)
                Label("Factory", systemImage: "arrow.counterclockwise").tag(Preset.factory.id)
            }
            Section("My Presets") {
                ForEach(store.userPresets) { preset in
                    HStack {
                        Label {
                            Text(preset.name).lineLimit(1)
                        } icon: {
                            PresetDot(lighting: preset.lighting)
                        }
                        Spacer(minLength: 4)
                        Menu {
                            presetActions(preset)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.button)
                        .buttonStyle(.borderless)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Rename, update or delete this preset")
                        .accessibilityLabel("Actions for \(preset.name)")
                    }
                    .tag(preset.id)
                    .contextMenu { presetActions(preset) }
                }
                .onMove { store.userPresets.move(fromOffsets: $0, toOffset: $1) }
                if store.userPresets.isEmpty {
                    Text("Set up the lights the way you like, then click New Preset.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onDeleteCommand {
            if let preset = store.userPresets.first(where: { $0.id == store.currentPresetID }) { deleting = preset }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                naming = NameRequest(name: "Preset \(store.userPresets.count + 1)")
            } label: {
                Label("New Preset", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .keyboardShortcut("n", modifiers: .command)
            .help("Save the current lighting as a preset (⌘N)")
            .padding(12)
        }
        .disabled(!store.connected)
    }

    @ViewBuilder private func presetActions(_ preset: Preset) -> some View {
        Button("Apply", systemImage: "checkmark.circle") { store.apply(preset) }
        Button("Rename…", systemImage: "pencil") { naming = NameRequest(preset: preset, name: preset.name) }
        Button("Update to Current Lighting", systemImage: "arrow.triangle.2.circlepath") { store.updatePreset(preset.id) }
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive) { deleting = preset }
    }

    private func select(_ id: Preset.ID?) {
        guard let preset = store.presets.first(where: { $0.id == id }) else { return }
        if preset.id == Preset.factory.id { confirmFactory = true } else { store.apply(preset) }
    }

    private func saveName() {
        guard let request = naming, !request.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let id = request.preset?.id, let i = store.userPresets.firstIndex(where: { $0.id == id }) {
            store.userPresets[i].name = request.name
        } else {
            store.saveAsPreset(named: request.name)
        }
    }

    // MARK: detail

    private var detail: some View {
        HStack(spacing: 0) {
            Hero(lighting: store.lighting, finish: $store.finish, focus: $focus, connected: store.connected)
                .frame(width: 310)
            Form {
                frontSection
                rearSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .disabled(!store.connected)
            .animation(.smooth(duration: 0.3), value: store.lighting.frontOn)
            .animation(.smooth(duration: 0.3), value: store.lighting.rearOn)
            .animation(.smooth(duration: 0.3), value: store.lighting.effect)
        }
        // Turn the mic to the side that just changed (both changed, e.g. a preset: keep it).
        .onChange(of: store.lighting) { old, new in
            var frontOnly = old, rearOnly = old
            (frontOnly.frontOn, frontOnly.frontColor, frontOnly.frontBrightness) = (new.frontOn, new.frontColor, new.frontBrightness)
            (rearOnly.rearOn, rearOnly.rearColor, rearOnly.rearBrightness, rearOnly.effect, rearOnly.speed) =
                (new.rearOn, new.rearColor, new.rearBrightness, new.effect, new.speed)
            if frontOnly == new { focus = .front } else if rearOnly == new { focus = .rear }
        }
        .safeAreaInset(edge: .top) {
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .glassEffect(.regular.tint(.orange), in: .capsule)
                    .padding(.top, 8)
            }
        }
    }

    private var frontSection: some View {
        Section {
            ZoneToggle(title: "Front", detail: "Light bar · 7 LEDs", isOn: $store.lighting.frontOn)
            if store.lighting.frontOn {
                LabeledContent("Color") { ColorField(color: $store.lighting.frontColor) }
                LabeledContent("Brightness") {
                    BrightnessSlider(value: $store.lighting.frontBrightness, tint: store.lighting.frontColor)
                }
            }
        }
    }

    private var rearSection: some View {
        Section {
            ZoneToggle(title: "Rear", detail: "Top row · 9 LEDs", isOn: $store.lighting.rearOn)
            if store.lighting.rearOn {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Effect")
                    EffectGrid(effect: $store.lighting.effect)
                }
                if store.lighting.effect == .solid {
                    LabeledContent("Color") { ColorField(color: $store.lighting.rearColor) }
                }
                if store.lighting.effect.usesSpeed {
                    LabeledContent("Speed") {
                        Slider(value: $store.lighting.speed, in: 0...9, step: 1) {
                            Text("Speed")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise").accessibilityLabel("Slow")
                        } maximumValueLabel: {
                            Image(systemName: "hare").accessibilityLabel("Fast")
                        }
                        .labelsHidden()
                    }
                }
                LabeledContent("Brightness") {
                    BrightnessSlider(value: $store.lighting.rearBrightness,
                                     tint: store.lighting.effect == .solid ? store.lighting.rearColor : nil)
                }
            }
        }
    }
}

/// The 3D mic with connection status, on the left of the window.
private struct Hero: View {
    let lighting: Lighting
    @Binding var finish: MicFinish
    @Binding var focus: MicFocus
    let connected: Bool

    var body: some View {
        VStack(spacing: 0) {
            ConnectionBadge(connected: connected)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 16)
            Mic3DView(lighting: lighting, whiteFinish: finish == .white, focus: focus)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 8)
                .help("Drag to turn the mic, click to flip it")
                .accessibilityAction(named: focus == .front ? "Show rear" : "Show front") {
                    focus = focus == .front ? .rear : .front
                }
            Picker("Mic finish", selection: $finish) {
                ForEach(MicFinish.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 140)
            .help("Color of your Capsule's housing")
            .padding(.bottom, 18)
        }
        .padding(.horizontal, 16)
        .background {
            // A faint pool of the front light under the mic; everything else stays neutral.
            RadialGradient(colors: [(lighting.frontOn ? lighting.frontColor.color : .clear).opacity(0.16), .clear],
                           center: .center, startRadius: 10, endRadius: 220)
                .animation(.smooth(duration: 0.5), value: lighting.frontColor)
        }
    }
}

/// First row of a zone: its name, where the LEDs sit, and the on/off switch.
private struct ZoneToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title).font(.headline)
            Text(detail)
        }
        .toggleStyle(.switch)
    }
}

/// Rear effects as quiet symbol tiles; the selected one carries the accent color.
struct EffectGrid: View {
    @Binding var effect: Effect

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
            ForEach(Effect.allCases) { e in
                let selected = effect == e
                Button { effect = e } label: {
                    VStack(spacing: 5) {
                        Image(systemName: e.symbol).font(.system(size: 15, weight: .medium)).frame(height: 18)
                        Text(e.name).font(.caption2).multilineTextAlignment(.center).lineLimit(2, reservesSpace: true)
                    }
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .padding(.vertical, 8).padding(.horizontal, 4)
                    .frame(maxWidth: .infinity)
                    .background(selected ? AnyShapeStyle(Color.accentColor.opacity(0.14)) : AnyShapeStyle(.fill.quaternary),
                                in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(selected ? 0.9 : 0), lineWidth: 1.5))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Brightness tinted with the zone's own color (accent for effects and near-white colors, which wouldn't show).
struct BrightnessSlider: View {
    @Binding var value: Double
    var tint: RGB? = nil

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: $value, in: 0...100) {
                Text("Brightness")
            } minimumValueLabel: {
                Image(systemName: "sun.min").accessibilityLabel("Dim")
            } maximumValueLabel: {
                Image(systemName: "sun.max").accessibilityLabel("Bright")
            }
            .labelsHidden()
            .tint(tintColor)
            Text("\(Int(value.rounded()))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
        }
    }

    private var tintColor: Color {
        guard let t = tint, min(t.r, t.g, t.b) < 200 else { return .accentColor }
        return t.color
    }
}
