import SceneKit
import SwiftUI

/// Which side of the mic the 3D view turns towards.
enum MicFocus { case front, rear }

/// 3D Capsule Elite in the current lighting, on a transparent background.
/// Drag to spin it (and tilt it a little), click to turn it around. A change of `focus` or `lighting`
/// turns it to the `focus` side with a critically damped spring; Reduce Motion snaps and freezes rear effects.
struct Mic3DView: NSViewRepresentable {
    var lighting: Lighting
    var whiteFinish: Bool
    var focus: MicFocus

    func makeCoordinator() -> MicModel { MicModel() }

    func makeNSView(context: Context) -> SCNView {
        let view = MicSCNView(frame: .zero, options: nil)
        view.model = context.coordinator
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        // shortcut: renders every frame while on screen (spring + effects); pause when idle if it shows up in Energy.
        view.isPlaying = true
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        view.setAccessibilityLabel("Capsule microphone")
        view.addGestureRecognizer(NSPanGestureRecognizer(target: view, action: #selector(MicSCNView.pan)))
        view.addGestureRecognizer(NSClickGestureRecognizer(target: view, action: #selector(MicSCNView.click)))
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.look = MicLook(lighting: lighting, whiteFinish: whiteFinish, focus: focus,
                                           reduceMotion: context.environment.accessibilityReduceMotion)
    }
}

final class MicSCNView: SCNView {
    weak var model: MicModel?
    private var last = CGPoint.zero

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    @objc func pan(_ g: NSPanGestureRecognizer) {
        let t = g.translation(in: self)
        if g.state == .began { last = .zero }
        let d = CGVector(dx: t.x - last.x, dy: t.y - last.y)
        last = t
        switch g.state {
        case .ended: model?.drag(by: d, ended: CGVector(dx: g.velocity(in: self).x, dy: g.velocity(in: self).y))
        case .cancelled, .failed: model?.drag(by: d, ended: .zero)
        default: model?.drag(by: d)
        }
    }

    @objc func click(_ g: NSClickGestureRecognizer) { model?.flip() }
}

#if DEBUG
#Preview("Mic 3D") {
    @Previewable @State var white = false
    @Previewable @State var rear = false
    var lighting = Lighting()
    lighting.frontColor = RGB(r: 0, g: 200, b: 255)
    return VStack {
        Mic3DView(lighting: lighting, whiteFinish: white, focus: rear ? .rear : .front)
            .frame(width: 320, height: 420)
        Toggle("White", isOn: $white)
        Toggle("Rear", isOn: $rear)
    }
    .padding()
    .background(.indigo.gradient)
}
#endif
