import SwiftUI
import RealityKit
import UIKit
import simd

struct VehicleCameraCommand { var serial = 0; var action = "reset"; var yaw: Float = .pi/4; var pitch: Float = atan(0.34); var zoom: Float? = nil }

private struct VehicleSceneAsset: Decodable {
    struct Part: Decodable { let id: String; let pivot: [Float]; let axis: [Float]; let openAngle: Float }
    struct Surface: Decodable { let color: [Float]; let roughness: Float; let metallic: Float; let unlit: Bool? }
    struct Mesh: Decodable { let name: String; let parent: String; let material: String; let positions: [Float]; let normals: [Float]; let triangles: [UInt32] }
    let schema: Int
    let parts: [Part]
    let materials: [String: Surface]
    let meshes: [Mesh]
    static func load() throws -> Self {
        let asset = try JSONDecoder().decode(Self.self, from: EmbeddedAppResources.data(named: "vehicle3d.json"))
        guard asset.schema == 1, asset.parts.count == 6, asset.meshes.count < 500 else { throw LocalError.message("3D 모델 형식 오류") }
        return asset
    }
}

@MainActor
final class VehicleARView: ARView {
    var didLayout: ((CGSize) -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); didLayout?(bounds.size) }
}

@MainActor
struct RealityVehicleView: UIViewRepresentable {
    let runtime: LocalRuntime
    let presentation: Object
    let command: VehicleCameraCommand
    let reducedMotion: Bool
    var appearance: VehicleAppearance = .original
    var backgroundColor = UIColor(red: 23/255, green: 24/255, blue: 26/255, alpha: 1)
    let onError: (String?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(runtime: runtime, onError: onError) }
    func makeUIView(context: Context) -> VehicleARView {
        let view = VehicleARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(backgroundColor)
        if backgroundColor.cgColor.alpha < 1 {
            view.backgroundColor = backgroundColor
            view.isOpaque = false
        }
        do { try context.coordinator.build(in: view) }
        catch { DispatchQueue.main.async { onError(error.localizedDescription) } }
        view.didLayout = { [weak coordinator = context.coordinator] size in coordinator?.layout(size) }
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:))); pan.maximumNumberOfTouches = 1; pan.delegate = context.coordinator; view.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:))); pinch.delegate = context.coordinator; view.addGestureRecognizer(pinch)
        let reset = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.reset(_:))); reset.numberOfTapsRequired = 2; view.addGestureRecognizer(reset)
        return view
    }
    func updateUIView(_ view: VehicleARView, context: Context) {
        view.environment.background = .color(backgroundColor)
        if backgroundColor.cgColor.alpha < 1 {
            view.backgroundColor = backgroundColor
            view.isOpaque = false
        }
        // v29: a display-only car (driving screens) must not swallow touches or cover overlays for hit testing.
        view.isUserInteractionEnabled = presentation.flag("allowInteraction")
        context.coordinator.applyAppearance(appearance)
        context.coordinator.apply(presentation, command: command, reduced: reducedMotion)
    }
    static func dismantleUIView(_ view: VehicleARView, coordinator: Coordinator) {
        view.didLayout = nil
        coordinator.stop()
        view.scene.anchors.removeAll()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let runtime: LocalRuntime
        private let onError: (String?) -> Void
        private let root = AnchorEntity(world: .zero)
        private let camera = PerspectiveCamera()
        /// v29: every car part hangs under `vehicle` so the car can yaw on the road while the camera stays put.
        private let vehicle = Entity()
        private var decor: DrivingSceneDecor?
        private var chargingDecor: ChargingSceneDecor?
        private var lookAhead: Float = 0
        private var lastYaw: Float = 0
        private var hinges: [String: Entity] = [:]
        private var definitions: [String: VehicleSceneAsset.Part] = [:]
        private var previous: [String: String] = [:]
        private var controllers: [String: AnimationPlaybackController] = [:]
        private var allow = false
        private var reduced = false
        private var yaw: Float = .pi/4
        private var pitch: Float = atan(0.34)
        private var zoom: Float = 1.08
        private var panStart: Float = 0
        private var pinchStart: Float = 1.08
        private var lastCommand = -1
        private var viewport = CGSize.zero
        private var cameraBoxes: [Object] = []
        private var expanded = Set<String>()
        private var closingUntil: [String: TimeInterval] = [:]
        private var displayLink: CADisplayLink?
        private var tween: (yaw: Float, zoom: Float, endYaw: Float, endZoom: Float, start: TimeInterval)?
        private var reportedCameraError = false
        private var lastAnimate = false
        private var surfaces: [(entity: ModelEntity, role: String, original: RealityKit.Material, source: VehicleSceneAsset.Mesh)] = []
        private var lastAppearance: VehicleAppearance?
        private var lastUVMapping: VehicleAppearance.Wrap?
        // v29 driving motion: wheel spin from live speed, smoothed steering yaw from route curvature.
        private var wheels: [Entity] = []
        private var wheelAngle: Float = 0
        private var wheelSpeed: Float = 0          // m/s
        private var motionLink: CADisplayLink?
        private var lastMotionTick: CFTimeInterval = 0
        init(runtime: LocalRuntime, onError: @escaping (String?) -> Void) { self.runtime = runtime; self.onError = onError; super.init() }
        /// Wheel hubs from the tyre meshes (rubber, low, outboard). Tyre/rim meshes inside a hub box spin with it.
        private var wheelBoxes: [(min: SIMD3<Float>, max: SIMD3<Float>, node: Entity)] = []
        private func prepareWheels(_ asset: VehicleSceneAsset) {
            for item in asset.meshes where item.parent == "body" && item.material == "rubber" {
                var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
                for i in stride(from: 0, to: item.positions.count, by: 3) {
                    let v = SIMD3(item.positions[i], item.positions[i+1], item.positions[i+2]); lo = simd_min(lo, v); hi = simd_max(hi, v)
                }
                // A tyre is roughly as tall as it is long and sits on the ground outboard.
                guard hi.y < 0.9, lo.y < 0.1, abs(lo.x + hi.x) > 1.0, (hi.y - lo.y) > 0.5, abs((hi.z - lo.z) - (hi.y - lo.y)) < 0.15 else { continue }
                let center = (lo + hi) / 2
                if let index = wheelBoxes.firstIndex(where: { simd_distance(($0.min + $0.max) / 2, center) < 0.25 }) {
                    wheelBoxes[index].min = simd_min(wheelBoxes[index].min, lo); wheelBoxes[index].max = simd_max(wheelBoxes[index].max, hi)
                } else {
                    let node = Entity(); node.name = "wheel"; node.position = center; vehicle.addChild(node)
                    wheelBoxes.append((lo, hi, node)); wheels.append(node)
                }
            }
        }
        private func wheelNode(for positions: [SIMD3<Float>]) -> Entity? {
            guard !positions.isEmpty else { return nil }
            let lo = positions.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1) }
            let hi = positions.reduce(SIMD3<Float>(repeating: -.infinity)) { simd_max($0, $1) }
            let pad = SIMD3<Float>(repeating: 0.03)
            guard let box = wheelBoxes.first(where: { all(lo .>= $0.min - pad) && all(hi .<= $0.max + pad) }) else { return nil }
            // Recentre the hub on the tyre's axle once the first mesh lands.
            return box.node
        }
        func build(in view: ARView) throws {
            let asset = try VehicleSceneAsset.load()
            root.addChild(vehicle)
            prepareWheels(asset)
            var bounds: [String: (min: SIMD3<Float>, max: SIMD3<Float>)] = [:]
            for part in asset.parts {
                guard part.pivot.count == 3, part.axis.count == 3 else { throw LocalError.message("3D 힌지 형식 오류") }
                let node = Entity(); node.name = part.id; node.position = SIMD3(part.pivot[0], part.pivot[1], part.pivot[2]); vehicle.addChild(node); hinges[part.id] = node; definitions[part.id] = part
            }
            for item in asset.meshes {
                guard item.positions.count % 3 == 0, item.normals.count == item.positions.count, item.triangles.count % 3 == 0,
                      item.positions.count < 300000, item.positions.allSatisfy({ $0.isFinite }), item.normals.allSatisfy({ $0.isFinite }),
                      item.triangles.allSatisfy({ Int($0) < item.positions.count/3 }), let surface = asset.materials[item.material], surface.color.count == 3 else { throw LocalError.message("3D 메시 형식 오류: \(item.name)") }
                func vectors(_ data: [Float]) -> [SIMD3<Float>] { stride(from: 0, to: data.count, by: 3).map { SIMD3(data[$0], data[$0+1], data[$0+2]) } }
                let positions = vectors(item.positions)
                var box: (min: SIMD3<Float>, max: SIMD3<Float>) = bounds[item.parent] ?? (SIMD3<Float>(repeating: .infinity), SIMD3<Float>(repeating: -.infinity))
                for point in positions { box.min = simd_min(box.min, point); box.max = simd_max(box.max, point) }
                bounds[item.parent] = box
                var descriptor = MeshDescriptor(name: item.name)
                descriptor.positions = MeshBuffers.Positions(positions); descriptor.normals = MeshBuffers.Normals(vectors(item.normals)); descriptor.primitives = .triangles(item.triangles)
                let color = UIColor(red: CGFloat(surface.color[0]), green: CGFloat(surface.color[1]), blue: CGFloat(surface.color[2]), alpha: 1)
                let material: RealityKit.Material
                if surface.unlit == true { material = UnlitMaterial(color: color) }
                else { material = SimpleMaterial(color: color, roughness: .float(surface.roughness), isMetallic: surface.metallic > 0.5) }
                let mesh = try MeshResource.generate(from: [descriptor]), entity = ModelEntity(mesh: mesh, materials: [material]); entity.name = item.name
                surfaces.append((entity, item.material, material, item))
                if item.parent == "body", let wheel = wheelNode(for: positions) { entity.position = -wheel.position; wheel.addChild(entity) }
                else if item.parent == "body" { vehicle.addChild(entity) }
                else { guard let hinge = hinges[item.parent] else { throw LocalError.message("3D 부품 연결 오류") }; hinge.addChild(entity) }
            }
            cameraBoxes = bounds.map { id, box in
                let part = definitions[id]
                return ["id": id, "min": [box.min.x, box.min.y, box.min.z], "max": [box.max.x, box.max.y, box.max.z],
                        "pivot": part?.pivot ?? [0, 0, 0], "axis": part?.axis ?? [0, 1, 0], "angle": part?.openAngle ?? 0] as Object
            }
            camera.camera.fieldOfViewInDegrees = 39; root.addChild(camera)
            let key = DirectionalLight(); key.light.color = .white; key.light.intensity = 3400; key.look(at: [0,0,0], from: [-3,6,5], relativeTo: nil); root.addChild(key)
            let fill = DirectionalLight(); fill.light.color = UIColor(red: 0.72, green: 0.84, blue: 1, alpha: 1); fill.light.intensity = 1300; fill.look(at: [0,0,0], from: [4,3,-4], relativeTo: nil); root.addChild(fill)
            view.scene.addAnchor(root)
        }
        func applyAppearance(_ raw: VehicleAppearance) {
            let value = raw.validated()
            guard value != lastAppearance else { return }
            do {
                // Create bounded, shared textures once per changed appearance, not per BLE tick.
                let paint = value.enabled ? try VehicleAppearanceMaterials.paint(value) : nil
                let plate = value.enabled ? try VehicleAppearanceMaterials.plate(value) : nil
                let glass = VehicleAppearanceMaterials.glass(value)
                for surface in surfaces {
                    var model = surface.entity.model!
                    if !value.enabled { model.materials = [surface.original] }
                    else if surface.role == "paint", let paint { model.materials = [paint] }
                    else if surface.role == "glass" { model.materials = [glass] }
                    else if ["import-1-body", "import-3-body"].contains(surface.entity.name), let plate { model.materials = [plate] }
                    if value.enabled && lastUVMapping != value.wrap && (surface.role == "paint" || ["import-1-body", "import-3-body"].contains(surface.entity.name)) {
                        model.mesh = try texturedMesh(surface.source, wrap: value.wrap)
                    }
                    surface.entity.model = model
                }
                lastAppearance = value
                if value.enabled { lastUVMapping = value.wrap }
            } catch { let message = error.localizedDescription; DispatchQueue.main.async { self.onError(message) } }
        }
        private func texturedMesh(_ item: VehicleSceneAsset.Mesh, wrap: VehicleAppearance.Wrap) throws -> MeshResource {
            let isPlate = ["import-1-body", "import-3-body"].contains(item.name)
            let pivot = definitions[item.parent]?.pivot ?? [0, 0, 0]
            let offset = SIMD3<Float>(pivot[0], pivot[1], pivot[2])
            func vector(_ values: [Float], _ index: Int) -> SIMD3<Float> { SIMD3(values[index*3], values[index*3+1], values[index*3+2]) }
            let originalPositions = stride(from: 0, to: item.positions.count/3, by: 1).map { vector(item.positions, $0) }
            let minimum = originalPositions.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1) }
            let maximum = originalPositions.reduce(SIMD3<Float>(repeating: -.infinity)) { simd_max($0, $1) }
            var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = []
            for triangle in stride(from: 0, to: item.triangles.count, by: 3) {
                let indices = (0..<3).map { Int(item.triangles[triangle+$0]) }
                let faceNormal = indices.map { vector(item.normals, $0) }.reduce(.zero, +)/3
                for index in indices {
                    let point = originalPositions[index]; positions.append(point); normals.append(vector(item.normals, index))
                    if isPlate {
                        var u = (point.x-minimum.x)/max(0.001, maximum.x-minimum.x)
                        if item.name == "import-3-body" { u = 1-u }
                        uv.append(SIMD2(u, (point.y-minimum.y)/max(0.001, maximum.y-minimum.y)))
                    } else { uv.append(VehicleAppearanceMaterials.wrapUV(point + offset, normal: faceNormal, wrap: wrap)) }
                }
            }
            var descriptor = MeshDescriptor(name: item.name)
            descriptor.positions = MeshBuffers.Positions(positions); descriptor.normals = MeshBuffers.Normals(normals)
            descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uv); descriptor.primitives = .triangles((0..<positions.count).map { UInt32($0) })
            return try MeshResource.generate(from: [descriptor])
        }
        func layout(_ size: CGSize) {
            guard size.width > 1, size.height > 1, size != viewport else { return }
            viewport = size; placeCamera()
        }
        func apply(_ state: Object, command: VehicleCameraCommand, reduced: Bool) {
            allow = state.flag("allowInteraction"); self.reduced = reduced
            let speedKmh = Float(state.number("wheelSpeedKmh") ?? 0)
            wheelSpeed = speedKmh.isFinite ? max(0, min(250, speedKmh)) / 3.6 : 0
            // v30 driving decor (road following the route, guide line, lights) only on driving screens.
            let driving = state["roadLanes"] != nil
            if driving, decor == nil { decor = DrivingSceneDecor(root: root, vehicle: vehicle) }
            decor?.configure(state, lightsEnabled: driving)
            // Charging decor: cable, flowing green energy wave, and pulsing port LED
            let charging = state.flag("charging") || (state.number("chargerKW") ?? 0) > 0.5 || state.flag("chargingDecor")
            if charging {
                if chargingDecor == nil { chargingDecor = ChargingSceneDecor(vehicle: vehicle) }
                chargingDecor?.setIsCharging(true)
            } else {
                chargingDecor?.setIsCharging(false)
            }
            let lead = Float(state.number("lookAhead") ?? 0)
            if lead.isFinite, abs(lead - lookAhead) > 0.01 { lookAhead = max(0, min(20, lead)); placeCamera() }
            updateMotionLink()
            let animate = state.flag("animate") && !reduced, states = state.object("states")
            if !animate && lastAnimate { controllers.values.forEach { $0.stop() }; controllers = [:]; previous = [:] }
            if !allow || reduced { stopTween() }
            lastAnimate = animate
            for (key, node) in hinges {
                let status = states.string(key, "unknown")
                guard previous[key] != status else { continue }; previous[key] = status
                controllers[key]?.stop(); controllers[key] = nil
                // Unknown freezes the displayed pose, never pretends the car has closed it.
                guard status != "unknown", let definition = definitions[key] else { continue }
                if status == "open" { expanded.insert(key); closingUntil[key] = nil }
                else if animate && expanded.contains(key) { closingUntil[key] = Date().timeIntervalSince1970 + 0.8 }
                else { expanded.remove(key); closingUntil[key] = nil }
                var transform = node.transform
                transform.rotation = simd_quatf(angle: status == "open" ? definition.openAngle : 0, axis: SIMD3(definition.axis[0], definition.axis[1], definition.axis[2]))
                if animate { controllers[key] = node.move(to: transform, relativeTo: root, duration: 0.7, timingFunction: .easeInOut) }
                else { node.transform = transform }
            }
            placeCamera()
            if lastCommand != command.serial {
                lastCommand = command.serial
                pitch = command.pitch.isFinite ? min(1.45, max(0.1, command.pitch)) : atan(0.34)
                var nextYaw = yaw, nextZoom = zoom
                switch command.action {
                case "angle": nextYaw = command.yaw; if let z = command.zoom, z.isFinite { nextZoom = min(2.5, max(1, z)) }
                case "in": nextZoom = max(1, zoom - 0.15)
                case "out": nextZoom = min(2.5, zoom + 0.15)
                default: nextYaw = .pi/4; nextZoom = 1.08
                }
                moveCamera(yaw: nextYaw, zoom: nextZoom, animated: allow && !reduced)
            }
        }
        private var motionActive: Bool {
            !UIAccessibility.isReduceMotionEnabled && (wheelSpeed > 0.1 || decor?.needsAnimation == true || chargingDecor?.needsAnimation == true)
        }
        private func updateMotionLink() {
            if motionActive, motionLink == nil {
                let link = CADisplayLink(target: self, selector: #selector(stepMotion(_:)))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
                lastMotionTick = CACurrentMediaTime(); motionLink = link; link.add(to: .main, forMode: .common)
            } else if !motionActive, motionLink != nil { motionLink?.invalidate(); motionLink = nil }
        }
        @objc private func stepMotion(_ link: CADisplayLink) {
            let now = CACurrentMediaTime(), dt = Float(min(0.1, max(0, now - lastMotionTick))); lastMotionTick = now
            // Rolling forward (+z): positive rotation about +x moves the tyre top toward +z.
            wheelAngle = (wheelAngle + wheelSpeed / 0.37 * dt).truncatingRemainder(dividingBy: 2 * .pi)
            for wheel in wheels { wheel.orientation = simd_quatf(angle: wheelAngle, axis: [1, 0, 0]) }
            if let decor { _ = decor.step(dt: dt, speed: wheelSpeed) }
            if let chargingDecor { chargingDecor.step(dt: dt) }
            if !motionActive { updateMotionLink() }
        }
        private func placeCamera() {
            guard viewport.width > 1, viewport.height > 1, !cameraBoxes.isEmpty else { return }
            let now = Date().timeIntervalSince1970
            for key in Array(closingUntil.keys) where (closingUntil[key] ?? 0) <= now {
                // An unknown state freezes a possibly intermediate pose, so keep its full envelope.
                if previous[key] == "closed" { expanded.remove(key) }
                closingUntil[key] = nil
            }
            do {
                let result = try runtime.call("vehicleCamera", ["boxes": cameraBoxes, "expanded": Array(expanded), "aspect": Double(viewport.width/viewport.height), "yaw": Double(yaw), "pitch": Double(pitch), "zoom": Double(zoom)]) as? Object ?? [:]
                guard let p = result["position"] as? [NSNumber], let t = result["target"] as? [NSNumber], p.count == 3, t.count == 3,
                      (p + t).allSatisfy({ $0.doubleValue.isFinite }) else { throw LocalError.message("3D 카메라 계산 오류") }
                // Chase views look past the car so the road ahead fills the frame (car sits lower).
                let lead = SIMD3<Float>(0, 0, lookAhead)
                camera.look(at: SIMD3(t[0].floatValue, t[1].floatValue, t[2].floatValue) + lead, from: SIMD3(p[0].floatValue, p[1].floatValue, p[2].floatValue) + lead * 0.35, relativeTo: root)
                if reportedCameraError { reportedCameraError = false; DispatchQueue.main.async { self.onError(nil) } }
            } catch {
                if !reportedCameraError { reportedCameraError = true; let message = error.localizedDescription; DispatchQueue.main.async { self.onError(message) } }
            }
        }
        private func stopTween() { displayLink?.invalidate(); displayLink = nil; tween = nil }
        private func moveCamera(yaw endYaw: Float, zoom endZoom: Float, animated: Bool) {
            stopTween()
            guard animated else { yaw = endYaw; zoom = endZoom; placeCamera(); return }
            let delta = atan2(sin(endYaw - yaw), cos(endYaw - yaw))
            tween = (yaw, zoom, yaw + delta, endZoom, CACurrentMediaTime())
            let link = CADisplayLink(target: self, selector: #selector(stepCamera(_:)))
            displayLink = link; link.add(to: .main, forMode: .common)
        }
        @objc private func stepCamera(_ link: CADisplayLink) {
            guard let tween else { stopTween(); return }
            let progress = Float(min(1, max(0, (CACurrentMediaTime() - tween.start)/0.38)))
            let eased = progress * progress * (3 - 2 * progress)
            yaw = tween.yaw + (tween.endYaw - tween.yaw) * eased
            zoom = tween.zoom + (tween.endZoom - tween.zoom) * eased
            placeCamera()
            if progress >= 1 { stopTween() }
        }
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard allow else { return }; if gesture.state == .began { stopTween(); panStart = yaw }
            yaw = panStart - Float(gesture.translation(in: gesture.view).x)*0.011
            placeCamera()
        }
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            guard allow else { return }; if gesture.state == .began { stopTween(); pinchStart = zoom }
            zoom = min(2.5, max(1, pinchStart/Float(max(0.1, gesture.scale)))); placeCamera()
        }
        @objc func reset(_ gesture: UITapGestureRecognizer) { guard allow else { return }; moveCamera(yaw: .pi/4, zoom: 1.08, animated: !reduced) }
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard allow else { return false }
            if let pan = gesture as? UIPanGestureRecognizer {
                let velocity = pan.velocity(in: pan.view)
                return abs(velocity.x) > abs(velocity.y)
            }
            return true
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { gestureRecognizer is UIPinchGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer }
        func stop() {
            controllers.values.forEach { $0.stop() }; controllers = [:]
            surfaces = []
            stopTween(); motionLink?.invalidate(); motionLink = nil
            // Release the driving decor with the scene: its entities must not outlive the RealityKit scene.
            decor?.teardown(); decor = nil
            chargingDecor?.teardown(); chargingDecor = nil
            hinges = [:]; definitions = [:]; previous = [:]; expanded = []; closingUntil = [:]
            root.children.forEach { $0.removeFromParent() }
        }
    }
}
