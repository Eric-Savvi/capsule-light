import AppIntents
import SwiftUI
import WidgetKit

/// Presets shown on the widget: the user's own first, "All Off" always last. Factory needs a confirmation, so it's app-only.
private func widgetPresets(_ count: Int) -> [Preset] {
    Array((AppGroup.load("presets") ?? [Preset]()).prefix(count - 1)) + [.allOff]
}

private enum WidgetMic {
    static let hid = CapsuleHID()

    static func waitForConnection() -> Bool {
        for _ in 0..<20 where !hid.isConnected { Thread.sleep(forTimeInterval: 0.05) }
        return hid.isConnected
    }
}

/// Applies a preset straight from the widget (the spike showed the extension can reach the mic over HID).
struct ApplyPresetIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply Capsule Preset"
    @Parameter(title: "Preset ID") var presetID: String

    init() {}
    init(_ id: UUID) { presetID = id.uuidString }

    func perform() async throws -> some IntentResult {
        guard let preset = widgetPresets(.max).first(where: { $0.id.uuidString == presetID }) else { return .result() }
        guard WidgetMic.waitForConnection() else { throw CapsuleHID.Failure.notConnected }
        let state = try DeviceState(reading: WidgetMic.hid)
        let current = Lighting(device: state, remembered: AppGroup.load("lighting") ?? Lighting())
        var target = preset.applied(to: current)
        if preset.id == Preset.allOff.id && !current.frontOn && !current.rearOn {
            (target.frontOn, target.rearOn) = (true, true) // second tap turns the lights back on
        }
        try target.device.write(to: WidgetMic.hid, over: state)
        AppGroup.save(target, as: "lighting")
        AppGroup.postChange()
        return .result()
    }
}

struct CapsuleEntry: TimelineEntry {
    var date = Date.now
    var lighting: Lighting
    var finish: MicFinish
    var connected: Bool
    var presets: [Preset]
}

struct CapsuleProvider: TimelineProvider {
    func placeholder(in context: Context) -> CapsuleEntry {
        CapsuleEntry(lighting: .factory, finish: .black, connected: true, presets: [.allOff])
    }

    func getSnapshot(in context: Context, completion: @escaping (CapsuleEntry) -> Void) { completion(entry(context)) }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CapsuleEntry>) -> Void) {
        completion(Timeline(entries: [entry(context)], policy: .after(.now + 15 * 60)))
    }

    /// Draws from what the app saved; only checks that the mic is plugged in (no commands sent).
    private func entry(_ context: Context) -> CapsuleEntry {
        CapsuleEntry(lighting: AppGroup.load("lighting") ?? .factory,
                     finish: AppGroup.load("finish") ?? .black,
                     connected: WidgetMic.waitForConnection(),
                     presets: widgetPresets(context.family == .systemSmall ? 2 : 4))
    }
}

struct CapsuleWidgetView: View {
    let entry: CapsuleEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 6) {
                    ConnectionBadge(connected: entry.connected)
                    mic
                    HStack(spacing: 6) { buttons }
                }
            } else {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        ConnectionBadge(connected: entry.connected)
                        mic
                    }
                    .frame(width: 110)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) { buttons }
                }
            }
        }
        .containerBackground(for: .widget) {
            ZStack {
                Color(white: entry.finish == .black ? 0.1 : 0.94)
                if entry.lighting.rearOn {
                    Circle().fill(entry.lighting.effect == .solid ? AnyShapeStyle(entry.lighting.rearColor.color)
                                                                  : entry.lighting.effectPreview(entry.lighting.effect))
                        .blur(radius: 40).opacity(0.45).offset(x: family == .systemSmall ? 0 : -90)
                }
            }
        }
        .environment(\.colorScheme, entry.finish == .black ? .dark : .light)
    }

    private var mic: some View {
        MicGlyph(lighting: entry.lighting, finish: entry.finish)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(entry.connected ? 1 : 0.4)
    }

    private var buttons: some View {
        ForEach(entry.presets) { preset in
            let allDark = !entry.lighting.frontOn && !entry.lighting.rearOn
            let name = preset.id == Preset.allOff.id && allDark ? "Lights On" : preset.name
            let current = preset.id != Preset.allOff.id && preset.lighting == entry.lighting
            Button(intent: ApplyPresetIntent(preset.id)) {
                HStack(spacing: 4) {
                    if preset.id == Preset.allOff.id {
                        Image(systemName: allDark ? "lightbulb" : "lightbulb.slash")
                    } else {
                        PresetDot(lighting: preset.lighting)
                    }
                    Text(name).lineLimit(1)
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(current ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.1), in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(!entry.connected)
        }
    }
}

@main
struct CapsuleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Capsule", provider: CapsuleProvider()) { CapsuleWidgetView(entry: $0) }
            .configurationDisplayName("Capsule")
            .description("Your mic's lighting and presets.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
