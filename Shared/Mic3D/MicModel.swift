import AppKit
import SceneKit

/// What the 3D mic should show. Written on the main thread, read on SceneKit's render thread.
struct MicLook {
    var lighting = Lighting(), whiteFinish = false, focus = MicFocus.front, reduceMotion = false
}

/// Procedural Capsule Elite (proportions and LED placement: docs/3d-reference.md).
/// Units are centimetres, origin at the centre of the mic body, front facing +z.
final class MicModel: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let camera = SCNNode()

    // Main thread writes look and drag input, the render thread animates; all of it under `lock`.
    private let lock = NSLock()
    private var _look = MicLook()
    private var motion = Motion()

    private let tilt = SCNNode(), turntable = SCNNode(), body = SCNNode()
    private let shell = pbr(), rearPlate = pbr(), mesh = pbr(), backing = pbr(), metal = pbr(), knurled = pbr(),
                stand = pbr()
    private var frontLEDs: [SCNMaterial] = [], frontGlows: [SCNMaterial] = []
    private var rearLEDs: [SCNMaterial] = [], rearGlows: [SCNMaterial] = []
    private var appliedFinish: Bool?

    // Measured from the side and front photos (docs/3d-reference.md).
    private static let w = 6.4, h = 17.0, back = -2.2
    /// Turntable angles that show the front or rear in three-quarter view.
    private static let frontYaw = -0.45, rearYaw = Double.pi - 0.45
    /// How far the body leans back on its joint.
    private static let lean = 0.16

    override init() {
        super.init()
        let (w, h, back) = (Self.w, Self.h, Self.back)

        // Body: shell, a deeper block below the grille for the knob, the domed grille cap on top.
        addBody(SCNBox(width: w, height: h, length: 3.0, chamferRadius: 0.6), shell, at: SCNVector3(0, 0, back + 1.5))
        addBody(SCNBox(width: w, height: 4.6, length: 2.4, chamferRadius: 0.6), shell, at: SCNVector3(0, -h / 2 + 2.3, 0.3))
        let capH = 12.9, capY = h / 2 - 0.1 - capH / 2, meshTile = CGSize(width: 0.17, height: 0.34)
        // Dark inner body so the mesh holes read as depth; same dome, a little smaller.
        addBody(MicGeometry.crownedSlab(width: w - 0.45, height: capH - 0.4, depth: 2.3, chamfer: 0.9, crown: 0.25, tile: meshTile),
                backing, at: SCNVector3(0, capY, 0.57))
        mesh.transparent.contents = MicGeometry.meshHoles
        mesh.transparencyMode = .aOne
        mesh.transparent.wrapS = .repeat
        mesh.transparent.wrapT = .repeat
        mesh.transparent.mipFilter = .linear
        addBody(MicGeometry.crownedSlab(width: w - 0.12, height: capH, depth: 2.6, chamfer: 1.05, crown: 0.25, tile: meshTile),
                mesh, at: SCNVector3(0, capY, 0.7))

        // Front: 7 LEDs between the inner body and the mesh, near its bottom; they blend into one bar.
        let ledY = capY - capH / 2 + 1.2, halfCap = (w - 0.12) / 2
        for i in 0..<7 {
            let x = -2.1 + Double(i) * 0.7, z = 2.0 + 0.25 * (1 - pow(x / halfCap, 2))
            let led = Self.led()
            frontLEDs.append(led)
            addBody(SCNBox(width: 0.74, height: 0.13, length: 0.05, chamferRadius: 0.06), led, at: SCNVector3(x, ledY, z - 0.14))
            let glow = Self.glow()
            frontGlows.append(glow)
            addBody(SCNPlane(width: 1.5, height: 1.0), glow, at: SCNVector3(x, ledY, z + 0.04)).eulerAngles.y = atan(0.5 * x / (halfCap * halfCap))
        }

        // Lower front: knurled gain knob (the brand logo is left out on purpose).
        let knobY = -h / 2 + 2.6
        let knob = SCNCylinder(radius: 0.72, height: 0.55)
        knob.materials = [knurled, metal, metal]
        addBody(knob, at: SCNVector3(-1.55, knobY, 1.5 + 0.27)).eulerAngles.x = .pi / 2

        // Headphone volume roller in the right side.
        let roller = SCNCylinder(radius: 0.9, height: 0.95)
        roller.materials = [knurled, metal, metal]
        addBody(roller, at: SCNVector3(w / 2 - 0.65, -h / 2 + 2.9, 0.1)).eulerAngles.x = .pi / 2

        // Sides: two staggered columns of holes towards the back.
        let hole = SCNCylinder(radius: 0.23, height: 0.02)
        let holeMat = SCNMaterial()
        holeMat.diffuse.contents = MicGeometry.sideHole
        holeMat.lightingModel = .constant
        hole.materials = [holeMat]
        let sides = SCNNode()
        for side in [-1.0, 1.0] {
            for row in 0..<19 {
                for (col, z) in [-1.3, -0.72].enumerated() {
                    let p = SCNVector3(side * (w / 2 + 0.006), h / 2 - 0.9 - Double(row) * 0.58 - Double(col) * 0.29, z)
                    sides.addChildNode(geometry: hole, at: p).eulerAngles.z = .pi / 2
                }
            }
        }
        body.addChildNode(sides.flattenedClone())

        // Rear: perforated plate (9 columns), dark backing behind it, the 9 rear LEDs behind its top row.
        let pitch = 0.58, rows = 25, plateH = Double(rows) * pitch, plateW = 9 * pitch
        let plate = SCNBox(width: plateW, height: plateH, length: 0.4, chamferRadius: 0.12)
        rearPlate.transparent.contents = MicGeometry.rearHole
        rearPlate.transparencyMode = .aOne
        rearPlate.transparent.wrapS = .repeat
        rearPlate.transparent.wrapT = .repeat
        rearPlate.transparent.mipFilter = .linear
        rearPlate.transparent.contentsTransform = SCNMatrix4MakeScale(9, CGFloat(rows), 1)
        plate.materials = [shell, shell, rearPlate, shell, shell, shell] // SCNBox faces: front, right, back, left, top, bottom
        addBody(plate, at: SCNVector3(0, 0, back + 0.05))
        addBody(SCNPlane(width: plateW, height: plateH), backing, at: SCNVector3(0, 0, back - 0.005)).eulerAngles.y = .pi
        for col in 0..<9 {
            let p = SCNVector3((Double(col) - 4) * pitch, plateH / 2 - pitch / 2, back - 0.01)
            let led = Self.led()
            rearLEDs.append(led)
            addBody(SCNCylinder(radius: 0.21, height: 0.005), led, at: p).eulerAngles.x = .pi / 2
            let glow = Self.glow()
            rearGlows.append(glow)
            addBody(SCNPlane(width: 1.5, height: 1.5), glow, at: SCNVector3(p.x, p.y, back - 0.25)).eulerAngles.y = .pi
        }

        // Stand: square base, post behind the body, knuckle joint the body leans back on.
        let ground = -h / 2 - 6.4, postZ = back - 1.1, joint = SCNVector3(0, -h / 2 + 3.5, postZ)
        add(SCNBox(width: 9.4, height: 0.55, length: 9.4, chamferRadius: 0.25), stand, at: SCNVector3(0, ground + 0.275, -1.1))
        add(SCNCylinder(radius: 0.7, height: joint.y - ground - 0.55), stand, at: SCNVector3(0, (joint.y + ground + 0.55) / 2, postZ))
        add(SCNCylinder(radius: 0.78, height: 1.5), stand, at: joint).eulerAngles.z = .pi / 2
        for side in [-1.0, 1.0] {
            add(SCNCylinder(radius: 0.32, height: 0.05), metal, at: SCNVector3(side * 0.76, joint.y, postZ)).eulerAngles.z = .pi / 2
        }
        addBody(SCNBox(width: 0.9, height: 0.9, length: 1.2, chamferRadius: 0.15), stand, at: SCNVector3(0, joint.y, back - 0.5))
        body.pivot = SCNMatrix4MakeTranslation(joint.x, joint.y, joint.z)
        body.position = joint
        body.eulerAngles.x = -Self.lean
        turntable.addChildNode(body)

        // Vertical drag tilts around the middle of the whole mic; the turntable spins around the body's axis.
        tilt.position = SCNVector3(0, -3.2, 0)
        turntable.position = SCNVector3(0, 3.2, 0)
        tilt.addChildNode(turntable)
        scene.rootNode.addChildNode(tilt)
        setUpLightsAndCamera()
    }

    private func setUpLightsAndCamera() {
        scene.lightingEnvironment.contents = MicGeometry.studio
        scene.lightingEnvironment.intensity = 1.4

        let cam = SCNCamera()
        cam.fieldOfView = 20
        cam.zNear = 10
        cam.zFar = 200
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.bloomIntensity = 1.4
        cam.bloomThreshold = 1.8
        cam.bloomBlurRadius = 7
        camera.camera = cam
        camera.position = SCNVector3(0, 4, 77)
        camera.look(at: SCNVector3(0, -3.3, 0))
        scene.rootNode.addChildNode(camera)

        let key = SCNLight()
        key.type = .directional
        key.intensity = 1100
        key.castsShadow = true
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowRadius = 4
        key.shadowSampleCount = 16
        key.shadowColor = NSColor(white: 0, alpha: 0.5)
        key.orthographicScale = 15
        light(key, angles: SCNVector3(-0.75, -0.55, 0))
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 700
        light(rim, angles: SCNVector3(-0.3, 2.5, 0))
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 120
        light(ambient, angles: SCNVector3(0, 0, 0))
    }

    private func light(_ l: SCNLight, angles: SCNVector3) {
        let n = SCNNode()
        n.light = l
        n.eulerAngles = angles
        scene.rootNode.addChildNode(n)
    }

    // MARK: Input (main thread)

    var look: MicLook {
        get { lock.withLock { _look } }
        set {
            lock.withLock {
                // Editing a side (focus or lighting changes) takes over from a manual angle.
                if newValue.focus != _look.focus || newValue.lighting != _look.lighting { motion.show(newValue.focus) }
                _look = newValue
            }
        }
    }

    /// Drag by a distance in points (AppKit: y up). Pass the release `velocity` (points/s) when the drag ends.
    func drag(by d: CGVector, ended velocity: CGVector? = nil) {
        lock.withLock { motion.drag(by: d, ended: velocity, momentum: !_look.reduceMotion) }
    }

    /// Turns to the other side.
    func flip() { lock.withLock { motion.flip() } }

    var yaw: Double { lock.withLock { motion.yaw ?? motion.yawTarget } }

    // MARK: Animation (render thread)

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) { update(at: time) }

    /// Applies `look` for `time`: finish, LED colors and the spring.
    func update(at time: TimeInterval) {
        let (look, yaw, pitch) = lock.withLock {
            motion.step(to: time, snap: _look.reduceMotion)
            return (_look, motion.yaw ?? 0, motion.pitch)
        }
        if look.whiteFinish != appliedFinish { applyFinish(white: look.whiteFinish) }
        turntable.eulerAngles.y = CGFloat(yaw)
        tilt.eulerAngles.x = CGFloat(pitch)
        let front = look.lighting.frontLED
        for i in frontLEDs.indices { Self.set(frontLEDs[i], frontGlows[i], front) }
        for (i, c) in look.lighting.rearLEDs(at: look.reduceMotion ? nil : time).enumerated() {
            Self.set(rearLEDs[i], rearGlows[i], c)
        }
    }

    private func applyFinish(white: Bool) {
        appliedFinish = white
        for m in [shell, rearPlate] { Self.paint(m, white ? 0.86 : 0.035, metalness: 0, roughness: white ? 0.42 : 0.5, clearCoat: 0.25) }
        Self.paint(mesh, white ? 0.78 : 0.16, metalness: white ? 1 : 0.6, roughness: white ? 0.32 : 0.5)
        Self.paint(backing, 0.01, metalness: 0, roughness: 0.9)
        Self.paint(metal, white ? 0.82 : 0.07, metalness: 1, roughness: white ? 0.22 : 0.35)
        Self.paint(knurled, white ? 0.82 : 0.07, metalness: 1, roughness: white ? 0.3 : 0.4)
        knurled.normal.contents = MicGeometry.knurl
        knurled.normal.wrapS = .repeat
        Self.paint(stand, white ? 0.8 : 0.04, metalness: white ? 1 : 0.6, roughness: white ? 0.28 : 0.4)
    }

    @discardableResult
    private func addBody(_ g: SCNGeometry, _ m: SCNMaterial? = nil, at p: SCNVector3) -> SCNNode {
        if let m { g.materials = [m] }
        return body.addChildNode(geometry: g, at: p)
    }

    @discardableResult
    private func add(_ g: SCNGeometry, _ m: SCNMaterial, at p: SCNVector3) -> SCNNode {
        g.materials = [m]
        return turntable.addChildNode(geometry: g, at: p)
    }

    // MARK: Materials

    private static func pbr() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        return m
    }

    private static func paint(_ m: SCNMaterial, _ gray: CGFloat, metalness: CGFloat, roughness: CGFloat, clearCoat: CGFloat = 0) {
        m.diffuse.contents = NSColor(white: gray, alpha: 1)
        m.metalness.contents = metalness
        m.roughness.contents = roughness
        m.clearCoat.contents = clearCoat
        m.clearCoatRoughness.contents = 0.25
    }

    private static func led() -> SCNMaterial {
        let m = pbr()
        paint(m, 0.03, metalness: 0, roughness: 0.4)
        m.emission.contents = NSColor.black
        m.emission.intensity = 4 // above 1 so the camera's bloom picks the LEDs up
        return m
    }

    private static func glow() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = MicGeometry.glow
        m.multiply.contents = NSColor.black
        m.blendMode = .add
        m.writesToDepthBuffer = false
        return m
    }

    private static func set(_ led: SCNMaterial, _ glow: SCNMaterial, _ c: SIMD3<Double>) {
        let color = NSColor(srgbRed: c.x, green: c.y, blue: c.z, alpha: 1)
        led.emission.contents = color
        glow.multiply.contents = color
    }
}

extension MicModel {
    static func yaw(for side: MicFocus) -> Double { side == .front ? frontYaw : rearYaw }
}

/// Turntable yaw and tilt pitch: follow the pointer while dragged, otherwise a critically damped spring to a target.
struct Motion {
    var yaw: Double?, yawVelocity = 0.0, yawTarget = MicModel.yaw(for: .front)
    var pitch = 0.0, pitchVelocity = 0.0, pitchTarget = 0.0
    var dragging = false, lastTime: TimeInterval?

    static let omega = 8.0, radiansPerPoint = 0.012, pitchLimit = 0.35

    /// Turns to `side` the shorter way round from wherever it is now (anticlockwise on a tie).
    mutating func show(_ side: MicFocus) {
        let target = MicModel.yaw(for: side), current = yaw ?? target
        yawTarget = target + 2 * .pi * floor((current - target) / (2 * .pi) + 0.5 + 1e-6)
        pitchTarget = 0
        dragging = false
    }

    /// Turns to the side it isn't showing, always the same way round.
    mutating func flip() {
        let current = yawTarget
        show(cos(current - MicModel.yaw(for: .front)) > 0 ? .rear : .front)
        if yawTarget < current { yawTarget += 2 * .pi }
        if yawTarget - current > 1.5 * .pi { yawTarget -= 2 * .pi }
    }

    mutating func drag(by d: CGVector, ended velocity: CGVector?, momentum: Bool) {
        guard let y = yaw else { return }
        dragging = velocity == nil
        yaw = y + d.dx * Self.radiansPerPoint
        pitch = min(max(pitch - d.dy * Self.radiansPerPoint * 0.5, -Self.pitchLimit), Self.pitchLimit)
        (yawTarget, pitchTarget, yawVelocity, pitchVelocity) = (yaw!, pitch, 0, 0)
        if let velocity, momentum {
            // Aim exactly where a critically damped spring released at this speed coasts to: no overshoot.
            yawVelocity = velocity.dx * Self.radiansPerPoint
            yawTarget += yawVelocity / Self.omega
        }
    }

    mutating func step(to time: TimeInterval, snap: Bool) {
        let dt = min(max(time - (lastTime ?? time), 0), 0.1)
        lastTime = time
        guard !dragging else { return }
        guard var y = yaw, !snap else {
            (yaw, yawVelocity, pitch, pitchVelocity) = (yawTarget, 0, pitchTarget, 0)
            return
        }
        Self.spring(&y, &yawVelocity, to: yawTarget, dt: dt)
        Self.spring(&pitch, &pitchVelocity, to: pitchTarget, dt: dt)
        yaw = y
    }

    /// Exact critically damped step, so any frame rate gives the same motion.
    private static func spring(_ x: inout Double, _ v: inout Double, to target: Double, dt: Double) {
        let x0 = x - target, k = v + omega * x0, e = exp(-omega * dt)
        x = target + (x0 + k * dt) * e
        v = (v - omega * k * dt) * e
    }
}

private extension SCNNode {
    @discardableResult
    func addChildNode(geometry: SCNGeometry, at p: SCNVector3) -> SCNNode {
        let n = SCNNode(geometry: geometry)
        n.position = p
        addChildNode(n)
        return n
    }
}
