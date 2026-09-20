import RealityKit
import UIKit
import simd

/// v30 driving scene around the 3D car: a lane road that follows the real route shape, an
/// FSD-style blue guide line to the recommended lane, and brake/tail/head light animation.
/// Car frame: origin under the car, heading +z, +x is the car's LEFT. Units are metres.
@MainActor
final class DrivingSceneDecor {
    enum Style: String { case asphalt, neon }
    /// Korean road painting differs by class: an undivided urban road has a double yellow centre line,
    /// a highway a single one, and a one-lane road none at all.
    enum RoadClass: String { case urban, highway, narrow }

    let road = Entity()
    private let lightRig = Entity()
    private let vehicle: Entity

    // Inputs
    private(set) var laneCount = 0
    private var laneTarget: Float = -1
    private var laneSuggested = false
    private var laneCenter: Float = 1
    private var style: Style = .asphalt
    private var roadClass: RoadClass = .urban
    private var steerTarget: Float = 0
    private var steer: Float = 0
    private var brakeTarget: Float = 0
    private var nightTarget: Float = 0

    // Route shape (x left, z forward) sampled every 10 m, re-anchored as the car travels.
    private var pathNow: [SIMD2<Float>] = []
    private var pathTarget: [SIMD2<Float>] = []
    private var hasRoutePath = false
    private var travel: Float = 0          // metres since the last path update
    private var odometer: Float = 0        // total metres, for mark scrolling
    private var lastYaw: Float = 0

    // Marks
    private enum Kind { case edge, dash, guide, centre, centreInner }
    private struct Mark { let entity: ModelEntity; let kind: Kind; let boundary: Int; let base: Float; let spacing: Float }
    private var marks: [Mark] = []
    private var ground: ModelEntity?
    private struct MarkSet { let container: Entity; let marks: [Mark]; let ground: ModelEntity }
    private var markSets: [Style: MarkSet] = [:]
    private var built: Bool { markSets[style] != nil }

    // Lights
    // RealityKit crashed (CoreRE MaterialParameterBlock) when materials were swapped every frame,
    // so each light is a stack of prebuilt sprites at fixed levels and only isEnabled changes.
    private var tailGlows: [LevelSprite] = []
    private var headGlows: [LevelSprite] = []
    private var beam: LevelSprite?
    private var brakePool: LevelSprite?
    private var lightsBuilt = false
    private var tail: Float = 0, brake: Float = 0, head: Float = 0.35
    private var applied: (tail: Float, brake: Float, head: Float) = (-1, -1, -1)
    private var glowTexture: TextureResource?
    private var beamTexture: TextureResource?
    private var barTexture: TextureResource?
    private var washTexture: TextureResource?

    private let laneWidth: Float = 3.4

    init(root: Entity, vehicle: Entity) {
        self.vehicle = vehicle
        root.addChild(road)
        vehicle.addChild(lightRig)
        road.isEnabled = false
        lightRig.isEnabled = false
    }

    /// Detach everything before the RealityKit scene goes away. Entities that outlive their scene
    /// have crashed the engine during teardown, so the view calls this from dismantleUIView.
    func teardown() {
        marks = []
        ground = nil
        for set in markSets.values { set.container.removeFromParent() }
        markSets = [:]
        for sprite in tailGlows + headGlows { sprite.remove() }
        tailGlows = []; headGlows = []
        beam?.remove(); beam = nil
        brakePool?.remove(); brakePool = nil
        lightsBuilt = false
        road.removeFromParent()
        lightRig.removeFromParent()
        glowTexture = nil; beamTexture = nil; barTexture = nil; washTexture = nil
    }

    var needsAnimation: Bool {
        abs(steerTarget - steer) > 0.001
            || (laneCount > 0 && laneSuggested && abs(laneTarget - laneCenter) > 0.002)
            || pathDiffers
            || abs(brakeTarget - brake) > 0.01 || abs(tailTarget - tail) > 0.01 || abs(headTarget - head) > 0.01
    }
    private var pathDiffers: Bool {
        guard pathNow.count == pathTarget.count else { return false }
        return zip(pathNow, pathTarget).contains { simd_distance($0, $1) > 0.02 }
    }
    private var tailTarget: Float { nightTarget * 0.55 }
    private var headTarget: Float { 0.35 + nightTarget * 0.65 }

    // MARK: Configuration (called on every presentation update, ~1 Hz)

    func configure(_ state: Object, lightsEnabled: Bool) {
        let newStyle = Style(rawValue: state.string("roadStyle", "asphalt")) ?? .asphalt
        if newStyle != style { style = newStyle; restyle() }
        roadClass = RoadClass(rawValue: state.string("roadClass", "urban")) ?? .urban
        let lanes = Int(state.number("roadLanes") ?? 0)
        if lanes > 0 { buildIfNeeded(); laneCount = min(6, max(1, lanes)) } else { laneCount = 0 }
        road.isEnabled = laneCount > 0
        laneSuggested = false
        if laneCount > 0 {
            if let target = state.number("roadLane"), target >= 0 {
                laneTarget = Float(min(Double(laneCount - 1), target)); laneSuggested = true
            } else {
                laneTarget = min(max(0, laneCenter), Float(laneCount - 1))
            }
            laneCenter = min(max(0, laneCenter), Float(laneCount - 1))
        }
        let bend = Float(state.number("steer") ?? 0)
        steerTarget = bend.isFinite ? max(-1, min(1, bend)) : 0
        if let flat = state["roadPath"] as? [NSNumber], flat.count >= 4, flat.count % 2 == 0 {
            var points: [SIMD2<Float>] = [.zero]
            for i in stride(from: 0, to: flat.count, by: 2) {
                let x = flat[i].floatValue, z = flat[i + 1].floatValue
                guard x.isFinite, z.isFinite, abs(x) < 400, abs(z) < 400 else { break }
                points.append(SIMD2(x, z))
            }
            if points.count >= 3 { setPath(points); hasRoutePath = true }
        } else {
            hasRoutePath = false
        }
        lightRig.isEnabled = lightsEnabled
        if lightsEnabled { buildLightsIfNeeded() }
        brakeTarget = state.flag("brake") ? 1 : 0
        let newNight: Float = state.flag("headlights") ? 1 : 0
        if abs(newNight - nightTarget) > 0.01 {
            nightTarget = newNight
            restyle()
        }
        if laneCount > 0 { layout() }
    }

    // MARK: Frame step

    /// Returns the car's yaw relative to the road for this frame.
    func step(dt: Float, speed: Float) -> Float {
        steer += (steerTarget - steer) * min(1, dt * 2.0)
        if !hasRoutePath { setPath(syntheticPath(), animated: false) }
        for i in pathNow.indices where i < pathTarget.count { pathNow[i] += (pathTarget[i] - pathNow[i]) * min(1, dt * 3) }
        travel += speed * dt
        odometer = (odometer + speed * dt).truncatingRemainder(dividingBy: 2400)
        let previousLane = laneCenter
        if laneCount > 0, laneSuggested { laneCenter += (laneTarget - laneCenter) * min(1, dt * 0.7) }
        let laneVelocity = (laneCenter - previousLane) / max(dt, 0.001)
        // Car heading follows the road just ahead; a lane change adds a small yaw toward the new lane.
        let ahead = pose(5).heading - pose(0).heading
        var yaw = ahead * 0.5 + laneVelocity * laneWidth / max(speed, 4) * -1
        yaw = max(-0.35, min(0.35, yaw))
        if abs(yaw - lastYaw) > 0.0002 { vehicle.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]); lastYaw = yaw }
        brake += (brakeTarget - brake) * min(1, dt * (brakeTarget > brake ? 14 : 5))
        tail += (tailTarget - tail) * min(1, dt * 3)
        head += (headTarget - head) * min(1, dt * 3)
        applyLights()
        if laneCount > 0 { layout() }
        return yaw
    }

    // MARK: Path

    private func syntheticPath() -> [SIMD2<Float>] {
        let curvature = steer * 0.008
        return (0...16).map { i in let z = Float(i) * 10; return SIMD2(curvature * z * z / 2, z) }
    }

    private func setPath(_ points: [SIMD2<Float>], animated: Bool = true) {
        if !pathNow.isEmpty, travel > 0.01 {
            // Re-express the current shape in the car's present frame before blending to the new one.
            let origin = rawPose(travel)
            pathNow = (0..<pathNow.count).map { i in toCar(rawPose(Float(i) * 10 + travel).point, origin: origin) }
        }
        travel = 0
        pathTarget = points
        if !animated || pathNow.count != points.count { pathNow = points }
    }

    private func toCar(_ p: SIMD2<Float>, origin: (point: SIMD2<Float>, heading: Float)) -> SIMD2<Float> {
        let d = p - origin.point, c = cos(origin.heading), s = sin(origin.heading)
        return SIMD2(d.x * c - d.y * s, d.x * s + d.y * c)
    }

    /// Pose on the stored route at arc length `s` (metres from its origin).
    /// The samples arrive every 10 m; a Catmull–Rom spline through them keeps the drawn road curved
    /// instead of showing a kink at every sample.
    private func rawPose(_ s: Float) -> (point: SIMD2<Float>, heading: Float) {
        guard pathNow.count >= 2 else { return (SIMD2(0, s), 0) }
        let last = pathNow.count - 1
        if s <= 0 {
            let h = heading(pathNow[0], pathNow[1])
            return (pathNow[0] + SIMD2(sin(h), cos(h)) * s, h)
        }
        if s >= Float(last) * 10 {
            let h = heading(pathNow[last - 1], pathNow[last])
            return (pathNow[last] + SIMD2(sin(h), cos(h)) * (s - Float(last) * 10), h)
        }
        let index = min(last - 1, Int(s / 10))
        let t = (s - Float(index) * 10) / 10
        func point(_ i: Int) -> SIMD2<Float> {
            if i < 0 { return pathNow[0] * 2 - pathNow[1] }               // mirror before the start
            if i > last { return pathNow[last] * 2 - pathNow[last - 1] }  // and after the end
            return pathNow[i]
        }
        let p0: SIMD2<Float> = point(index - 1)
        let p1: SIMD2<Float> = point(index)
        let p2: SIMD2<Float> = point(index + 1)
        let p3: SIMD2<Float> = point(index + 2)
        let t2: Float = t * t
        let t3: Float = t2 * t
        // Catmull–Rom basis, written step by step so the type checker stays fast.
        let a0: SIMD2<Float> = p1 * 2
        let a1: SIMD2<Float> = p2 - p0
        var a2: SIMD2<Float> = p0 * 2
        a2 -= p1 * 5
        a2 += p2 * 4
        a2 -= p3
        var a3: SIMD2<Float> = p1 * 3
        a3 -= p0
        a3 -= p2 * 3
        a3 += p3
        var position: SIMD2<Float> = a0
        position += a1 * t
        position += a2 * t2
        position += a3 * t3
        position *= 0.5
        var tangent: SIMD2<Float> = a1
        tangent += a2 * (2 * t)
        tangent += a3 * (3 * t2)
        let h: Float = simd_length(tangent) > 0.0001 ? atan2(tangent.x, tangent.y) : heading(p1, p2)
        return (position, h)
    }

    private func heading(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let d = b - a
        return simd_length(d) > 0.001 ? atan2(d.x, d.y) : 0
    }

    /// Pose in the car's current frame at `s` metres ahead (negative = behind).
    private func pose(_ s: Float) -> (point: SIMD2<Float>, heading: Float) {
        let origin = rawPose(travel), p = rawPose(s + travel)
        return (toCar(p.point, origin: origin), p.heading - origin.heading)
    }

    // MARK: Road marks

    private func buildIfNeeded() {
        if let set = markSets[style] {
            if ground !== set.ground { activate(set) }
            return
        }
        let container = Entity()
        road.addChild(container)
        var marks: [Mark] = []
        let groundEntity = ModelEntity(mesh: .generatePlane(width: 180, depth: 180), materials: [groundMaterial()])
        groundEntity.position = [0, -0.015, 20]
        container.addChild(groundEntity)
        let lineMesh = MeshResource.generateBox(width: 0.13, height: 0.006, depth: 3.05)
        let dashMesh = MeshResource.generateBox(width: 0.13, height: 0.006, depth: 3.0)
        let guideMesh = MeshResource.generateBox(width: 0.40, height: 0.008, depth: 2.05)
        for i in 0..<42 {
            // Right-hand road edge: white solid.
            let e = ModelEntity(mesh: lineMesh, materials: [edgeMaterial()]); container.addChild(e)
            marks.append(Mark(entity: e, kind: .edge, boundary: 1, base: Float(i) * 3 - 30, spacing: 3))
            // Centre line on the left: yellow, doubled on undivided roads.
            let c = ModelEntity(mesh: lineMesh, materials: [centreMaterial()]); container.addChild(c)
            marks.append(Mark(entity: c, kind: .centre, boundary: 0, base: Float(i) * 3 - 30, spacing: 3))
            let c2 = ModelEntity(mesh: lineMesh, materials: [centreMaterial()]); container.addChild(c2)
            marks.append(Mark(entity: c2, kind: .centreInner, boundary: 0, base: Float(i) * 3 - 30, spacing: 3))
        }
        for boundary in 1...5 {
            for i in 0..<16 {
                let e = ModelEntity(mesh: dashMesh, materials: [dashMaterial()]); container.addChild(e)
                marks.append(Mark(entity: e, kind: .dash, boundary: boundary, base: Float(i) * 8 - 30, spacing: 8))
            }
        }
        for i in 0..<44 {
            let e = ModelEntity(mesh: guideMesh, materials: [guideMaterial()]); container.addChild(e)
            marks.append(Mark(entity: e, kind: .guide, boundary: -1, base: 1.5 + Float(i) * 2, spacing: 0))
        }
        // FSD Context 1: Stop Line (white bar across lane in front of car)
        let stopLineMesh = MeshResource.generateBox(width: 3.6, height: 0.008, depth: 0.48)
        let stopLine = ModelEntity(mesh: stopLineMesh, materials: [edgeMaterial()])
        stopLine.position = [0, 0.005, 3.2]
        container.addChild(stopLine)

        // FSD Context 2: Lane Bollards / Flexible Posts (white cylinder with orange reflective bands on left edge)
        let postMesh = MeshResource.generateCylinder(height: 0.75, radius: 0.042)
        let bandMesh = MeshResource.generateCylinder(height: 0.14, radius: 0.044)
        var postMat = UnlitMaterial(color: UIColor(white: 0.95, alpha: 0.95))
        var bandMat = UnlitMaterial(color: UIColor(red: 1.0, green: 0.48, blue: 0.12, alpha: 0.95))
        for zOffset: Float in [-2, 2, 6, 10, 14, 18, 22] {
            let postRoot = Entity()
            let p = ModelEntity(mesh: postMesh, materials: [postMat])
            p.position.y = 0.375
            let b1 = ModelEntity(mesh: bandMesh, materials: [bandMat])
            b1.position.y = 0.52
            let b2 = ModelEntity(mesh: bandMesh, materials: [bandMat])
            b2.position.y = 0.30
            postRoot.addChild(p); postRoot.addChild(b1); postRoot.addChild(b2)
            postRoot.position = [-laneWidth * 0.5 - 0.22, 0, zOffset]
            container.addChild(postRoot)
        }

        // FSD Context 3: Adjacent Vehicle (stylized car waiting in right lane)
        let adjCar = Entity()
        let bodyMesh = MeshResource.generateBox(width: 1.88, height: 0.95, depth: 4.45)
        let cabinMesh = MeshResource.generateBox(width: 1.55, height: 0.58, depth: 2.30)
        var carMat = UnlitMaterial(color: UIColor(red: 0.78, green: 0.80, blue: 0.84, alpha: 0.92))
        var glassMat = UnlitMaterial(color: UIColor(red: 0.15, green: 0.18, blue: 0.22, alpha: 0.95))
        let bEnt = ModelEntity(mesh: bodyMesh, materials: [carMat])
        bEnt.position = [0, 0.48, 0]
        let cEnt = ModelEntity(mesh: cabinMesh, materials: [glassMat])
        cEnt.position = [0, 1.05, -0.2]
        adjCar.addChild(bEnt)
        adjCar.addChild(cEnt)
        adjCar.position = [laneWidth * 1.05, 0, 1.4]
        container.addChild(adjCar)

        // FSD Context 4: Traffic Signals (twin signal posts with green lights ahead)
        let signalRoot = Entity()
        let boxMesh = MeshResource.generateBox(width: 0.32, height: 0.95, depth: 0.22)
        var signalMat = UnlitMaterial(color: UIColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1))
        let greenMesh = MeshResource.generatePlane(width: 0.24, height: 0.24)
        var greenMat = UnlitMaterial(color: UIColor(red: 0.15, green: 0.95, blue: 0.35, alpha: 1))
        for xOffset: Float in [-0.85, 0.85] {
            let box = ModelEntity(mesh: boxMesh, materials: [signalMat])
            let light = ModelEntity(mesh: greenMesh, materials: [greenMat])
            light.position = [0, -0.18, -0.12]
            light.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
            box.addChild(light)
            box.position = [xOffset, 3.6, 26]
            signalRoot.addChild(box)
        }
        container.addChild(signalRoot)

        let set = MarkSet(container: container, marks: marks, ground: groundEntity)
        markSets[style] = set
        activate(set)
    }

    private func activate(_ set: MarkSet) {
        for other in markSets.values where other.container !== set.container { other.container.isEnabled = false }
        set.container.isEnabled = true
        marks = set.marks
        ground = set.ground
    }

    private func restyle() {
        // Only switch prebuilt sets; a set for the new style is built on first use.
        guard markSets[style] != nil || !markSets.isEmpty else { return }
        buildIfNeeded()
    }

    private func groundMaterial() -> UnlitMaterial {
        if style == .neon {
            var m = UnlitMaterial(color: UIColor(red: 0.02, green: 0.05, blue: 0.14, alpha: 1))
            m.blending = .transparent(opacity: .init(floatLiteral: 0.55))
            return m
        }
        let isNight = nightTarget > 0.5
        let groundColor = isNight
            ? UIColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1) // Tesla Night Dark Asphalt
            : UIColor(red: 0.82, green: 0.84, blue: 0.88, alpha: 1) // Tesla Daytime Light Slate Asphalt
        var m = UnlitMaterial(color: groundColor)
        m.blending = .transparent(opacity: .init(floatLiteral: 0.95))
        return m
    }
    private func edgeMaterial() -> UnlitMaterial {
        var m = UnlitMaterial(color: UIColor(white: 0.95, alpha: 1))
        m.blending = .transparent(opacity: .init(floatLiteral: style == .neon ? 0.7 : 0.92))
        return m
    }
    private func centreMaterial() -> UnlitMaterial {
        var m = UnlitMaterial(color: UIColor(red: 1.0, green: 0.72, blue: 0.16, alpha: 1))
        m.blending = .transparent(opacity: .init(floatLiteral: style == .neon ? 0.8 : 0.95))
        return m
    }
    private func dashMaterial() -> UnlitMaterial {
        var m = UnlitMaterial(color: UIColor(white: 0.95, alpha: 1))
        m.blending = .transparent(opacity: .init(floatLiteral: style == .neon ? 0.6 : 0.88))
        return m
    }
    private func guideMaterial() -> UnlitMaterial {
        var m = UnlitMaterial(color: UIColor(red: 0.10, green: 0.46, blue: 1, alpha: 1))
        m.blending = .transparent(opacity: .init(floatLiteral: 0.75))
        return m
    }

    private func layout() {
        let n = laneCount
        // Guide line: from the car's lane centre, S-curve into the recommended lane between 6 m and 38 m.
        let shift = laneSuggested ? (laneCenter - laneTarget) * laneWidth : 0
        for mark in marks {
            let visible: Bool
            var s: Float
            var lateral: Float
            switch mark.kind {
            case .edge:
                visible = true
                s = mark.base - odometer.truncatingRemainder(dividingBy: mark.spacing)
                lateral = (laneCenter + 0.5 - Float(n)) * laneWidth
            case .centre:
                // A one-lane road has no centre line; everything else has one on the left.
                visible = roadClass != .narrow && n > 1
                s = mark.base - odometer.truncatingRemainder(dividingBy: mark.spacing)
                lateral = (laneCenter + 0.5) * laneWidth
            case .centreInner:
                visible = roadClass == .urban && n > 1   // undivided road: double yellow
                s = mark.base - odometer.truncatingRemainder(dividingBy: mark.spacing)
                lateral = (laneCenter + 0.5) * laneWidth - 0.26
            case .dash:
                visible = mark.boundary < n
                s = mark.base - odometer.truncatingRemainder(dividingBy: mark.spacing)
                lateral = (laneCenter + 0.5 - Float(mark.boundary)) * laneWidth
            case .guide:
                visible = laneSuggested
                s = mark.base
                let t = max(0, min(1, (s - 6) / 32))
                lateral = shift * (t * t * (3 - 2 * t))
            }
            mark.entity.isEnabled = visible && s > -32 && s < 96
            guard mark.entity.isEnabled else { continue }
            let p = pose(s)
            let normal = SIMD2<Float>(cos(p.heading), -sin(p.heading))
            let xz = p.point + normal * lateral
            mark.entity.position = [xz.x, mark.kind == .guide ? 0.004 : 0, xz.y]
            mark.entity.orientation = simd_quatf(angle: p.heading, axis: [0, 1, 0])
        }
    }

    // MARK: Lights

    private func buildLightsIfNeeded() {
        guard !lightsBuilt else { return }
        lightsBuilt = true
        glowTexture = Self.radialTexture()
        beamTexture = Self.beamTexture()
        barTexture = Self.barTexture()
        washTexture = Self.washTexture()
        let red = UIColor(red: 1, green: 0.10, blue: 0.06, alpha: 1)
        let white = UIColor(red: 0.92, green: 0.97, blue: 1, alpha: 1)
        // One slim bar across the tail, like the car's own light strip, rather than two round blobs.
        let tailMesh = MeshResource.generatePlane(width: 1.86, height: 0.12)
        let bar = LevelSprite(parent: lightRig, mesh: tailMesh) { barMaterial(red, $0) }
        bar.root.position = [0, 1.06, -2.37]
        bar.root.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        tailGlows.append(bar)
        let tipMesh = MeshResource.generatePlane(width: 0.34, height: 0.1)
        for x: Float in [0.74, -0.74] {
            let sprite = LevelSprite(parent: lightRig, mesh: tipMesh) { barMaterial(red, $0 * 0.9) }
            sprite.root.position = [x, 1.05, -2.36]
            sprite.root.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
            tailGlows.append(sprite)
        }
        let headMesh = MeshResource.generatePlane(width: 0.62, height: 0.16)
        for x: Float in [0.62, -0.62] {
            let sprite = LevelSprite(parent: lightRig, mesh: headMesh) { barMaterial(white, $0) }
            sprite.root.position = [x, 0.82, 2.43]
            headGlows.append(sprite)
        }
        if let beamTexture {
            // Narrower, dimmer pool of light in front of the car; the road itself stays readable.
            let sprite = LevelSprite(parent: lightRig, mesh: .generatePlane(width: 4.6, depth: 13)) { level in
                var m = UnlitMaterial()
                m.color = .init(tint: UIColor(red: 0.86, green: 0.92, blue: 1, alpha: 1), texture: .init(beamTexture))
                m.blending = .transparent(opacity: .init(scale: level * 0.3, texture: .init(beamTexture)))
                return m
            }
            sprite.root.position = [0, 0.01, 8.6]
            beam = sprite
        }
        // Vibrant red wash on the asphalt behind the car: covers lane width, smooth falloff matching Tesla FSD night view
        let pool = LevelSprite(parent: lightRig, mesh: .generatePlane(width: 3.6, depth: 5.2)) { washMaterial(red, $0 * 0.85) }
        pool.root.position = [0, 0.012, -3.2]
        brakePool = pool
    }

    /// Light bar: a horizontal gradient so the ends fade out instead of ending in a hard edge.
    private func barMaterial(_ tint: UIColor, _ alpha: Float) -> UnlitMaterial {
        var m = UnlitMaterial()
        if let barTexture {
            m.color = .init(tint: tint, texture: .init(barTexture))
            m.blending = .transparent(opacity: .init(scale: alpha, texture: .init(barTexture)))
        } else {
            m.color = .init(tint: tint)
            m.blending = .transparent(opacity: .init(floatLiteral: alpha))
        }
        return m
    }
    /// Road wash: strongest right behind the car, fading out along the road and to the sides.
    private func washMaterial(_ tint: UIColor, _ alpha: Float) -> UnlitMaterial {
        var m = UnlitMaterial()
        if let washTexture {
            m.color = .init(tint: tint, texture: .init(washTexture))
            m.blending = .transparent(opacity: .init(scale: alpha, texture: .init(washTexture)))
        } else {
            m.color = .init(tint: tint)
            m.blending = .transparent(opacity: .init(floatLiteral: alpha * 0.5))
        }
        return m
    }

    private func glowMaterial(_ tint: UIColor, _ alpha: Float) -> UnlitMaterial {
        var m = UnlitMaterial()
        if let glowTexture {
            m.color = .init(tint: tint, texture: .init(glowTexture))
            m.blending = .transparent(opacity: .init(scale: alpha, texture: .init(glowTexture)))
        } else {
            m.color = .init(tint: tint)
            m.blending = .transparent(opacity: .init(floatLiteral: alpha))
        }
        return m
    }

    private func applyLights() {
        guard lightsBuilt else { return }
        let red = max(tail * 0.6, brake)
        tailGlows.forEach { $0.set(red) }
        brakePool?.set(brake)
        headGlows.forEach { $0.set(head) }
        beam?.set(max(0, head - 0.35) / 0.65)
        applied = (red, brake, head)
    }

    private static func radialTexture() -> TextureResource? {
        let size = 96
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [UIColor.white.cgColor, UIColor(white: 1, alpha: 0.55).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray,
                                        locations: [0, 0.35, 1]) else { return nil }
        let c = CGPoint(x: size / 2, y: size / 2)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(size / 2), options: [])
        guard let image = ctx.makeImage() else { return nil }
        return try? TextureResource.generate(from: image, options: .init(semantic: .color))
    }

    /// Horizontal bar: bright in the middle, feathered at both ends and top/bottom.
    private static func barTexture() -> TextureResource? {
        let w = 128, h = 16
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for y in 0..<h {
            let v = abs(Float(y) / Float(h - 1) - 0.5) * 2
            let across = pow(max(0, 1 - v * v), 1.4)
            for x in 0..<w {
                let u = abs(Float(x) / Float(w - 1) - 0.5) * 2
                let along = u < 0.82 ? 1 : max(0, 1 - (u - 0.82) / 0.18)
                let a = UInt8(max(0, min(255, across * along * 255)))
                let i = (y * w + x) * 4
                pixels[i] = a; pixels[i + 1] = a; pixels[i + 2] = a; pixels[i + 3] = a
            }
        }
        guard let image = ctx.makeImage() else { return nil }
        return try? TextureResource.generate(from: image, options: .init(semantic: .color))
    }

    /// Reflection on the road: strong near the car, gone by the far end, feathered at the sides.
    private static func washTexture() -> TextureResource? {
        let w = 64, h = 128
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for y in 0..<h {
            let v = Float(y) / Float(h - 1)          // 0 near the car, 1 far behind
            let along = pow(max(0, 1 - v), 2.2)
            for x in 0..<w {
                let u = abs(Float(x) / Float(w - 1) - 0.5) * 2
                let across = pow(max(0, 1 - u * u), 1.6)
                let a = UInt8(max(0, min(255, along * across * 255)))
                let i = (y * w + x) * 4
                pixels[i] = a; pixels[i + 1] = a; pixels[i + 2] = a; pixels[i + 3] = a
            }
        }
        guard let image = ctx.makeImage() else { return nil }
        return try? TextureResource.generate(from: image, options: .init(semantic: .color))
    }

    private static func beamTexture() -> TextureResource? {
        let w = 64, h = 160
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for y in 0..<h {
            // v = 0 near the car, 1 far away (plane depth maps to texture v).
            let v = Float(y) / Float(h - 1)
            let spread = 0.18 + 0.32 * v
            for x in 0..<w {
                let u = (Float(x) / Float(w - 1) - 0.5)
                let across = exp(-(u * u) / (2 * spread * spread))
                let along = pow(max(0, 1 - v), 1.8) * min(1, v * 6 + 0.15)
                let a = UInt8(max(0, min(255, across * along * 255)))
                let i = (y * w + x) * 4
                pixels[i] = a; pixels[i + 1] = a; pixels[i + 2] = a; pixels[i + 3] = a
            }
        }
        guard let image = ctx.makeImage() else { return nil }
        return try? TextureResource.generate(from: image, options: .init(semantic: .color))
    }
}

/// A light drawn as prebuilt sprites at fixed intensity steps; changing intensity only toggles isEnabled.
@MainActor
private final class LevelSprite {
    static let steps: [Float] = [0.2, 0.4, 0.6, 0.8, 1.0]
    let root = Entity()
    private var sprites: [ModelEntity] = []
    private var shown = -1

    init(parent: Entity, mesh: MeshResource, material: (Float) -> UnlitMaterial) {
        parent.addChild(root)
        for level in Self.steps {
            let e = ModelEntity(mesh: mesh, materials: [material(level)])
            e.isEnabled = false
            root.addChild(e)
            sprites.append(e)
        }
    }

    func remove() {
        for sprite in sprites { sprite.removeFromParent() }
        sprites = []
        root.removeFromParent()
        shown = -1
    }

    func set(_ level: Float) {
        let clamped = level.isFinite ? max(0, min(1, level)) : 0
        let index = Int((clamped * Float(Self.steps.count)).rounded()) - 1   // -1 = off
        guard index != shown else { return }
        if shown >= 0 { sprites[shown].isEnabled = false }
        if index >= 0 { sprites[index].isEnabled = true }
        shown = index
    }
}
