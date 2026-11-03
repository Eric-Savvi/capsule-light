import Foundation
import Observation
import WidgetKit

/// App state: what the mic shows, the user's presets, and rate-limited writes to the mic.
@MainActor @Observable
final class Store {
    static let shared = Store()
    private(set) var connected = false
    var error: String?
    var lighting = Lighting() {
        didSet {
            guard !loading, lighting != oldValue else { return }
            AppGroup.save(lighting, as: "lighting")
            scheduleWrite()
        }
    }
    var userPresets: [Preset] = AppGroup.load("presets") ?? [] {
        didSet { AppGroup.save(userPresets, as: "presets"); WidgetCenter.shared.reloadAllTimelines() }
    }
    var presets: [Preset] { [.factory, .allOff] + userPresets }
    var finish: MicFinish = AppGroup.load("finish") ?? .black {
        didSet { AppGroup.save(finish, as: "finish"); WidgetCenter.shared.reloadAllTimelines() }
    }

    @ObservationIgnored private let hid = CapsuleHID()
    @ObservationIgnored private var written: DeviceState? // what the mic has now
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var writePending = false
    @ObservationIgnored private var lastWrite = Date.distantPast

    private init() {
        lighting = AppGroup.load("lighting") ?? Lighting()
        hid.onConnectionChange = { [weak self] up in
            MainActor.assumeIsolated {
                self?.connected = up
                self?.error = nil
                if up { self?.reload() } else { self?.written = nil }
            }
        }
        // The widget wrote to the mic: take its state.
        AppGroup.observeChanges { Store.shared.reload() }
    }

    /// The mic is the source of truth: take its state, keeping remembered settings for zones that are off.
    func reload() {
        do {
            let state = try DeviceState(reading: hid)
            loading = true
            lighting = Lighting(device: state, remembered: lighting)
            loading = false
            written = state
            AppGroup.save(lighting, as: "lighting") // the widget draws from this, it never reads the mic
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func apply(_ preset: Preset) { lighting = preset.applied(to: lighting) }

    /// The preset whose lighting is on the mic right now, if any.
    var currentPresetID: Preset.ID? {
        presets.first { $0.applied(to: lighting) == lighting }?.id
    }

    func saveAsPreset(named name: String) {
        userPresets.append(Preset(name: name, lighting: lighting))
    }

    func updatePreset(_ id: Preset.ID) {
        if let i = userPresets.firstIndex(where: { $0.id == id }) { userPresets[i].lighting = lighting }
    }

    // MARK: writing

    /// At most one write per 300 ms; the last change always gets written (the mic stores every write).
    private func scheduleWrite() {
        guard !writePending else { return }
        writePending = true
        let wait = max(0, 0.3 - Date().timeIntervalSince(lastWrite))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [self] in
            writePending = false
            lastWrite = Date()
            flush()
        }
    }

    private func flush() {
        guard connected else { return }
        let target = lighting.device
        guard target != written else { return }
        do {
            try target.write(to: hid, over: written)
            written = target
            error = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Safety rule 3: stop, report, and resync with what the mic really has.
            self.error = error.localizedDescription
            written = nil
            reload()
        }
    }
}
