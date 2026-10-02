import SwiftUI
import RealityKit
import UIKit

/// v1.28: rigged 3D character (Tripo mesh + Mixamo motion capture, retargeted, root motion removed).
/// Clips cross-fade by vehicle speed, so motion is continuous; drag to orbit and view from any side.
@MainActor
final class CharacterRig {
    static let shared = CharacterRig()
    private(set) var model: Entity?
    private(set) var clips: [String: AnimationResource] = [:]
    private(set) var failed = false
    private(set) var loadError: String?
    private init() {
        guard let dir = Bundle.main.url(forResource: "character", withExtension: nil) else { failed = true; loadError = "character 폴더 없음"; return }
        do {
            let body = try Entity.load(contentsOf: dir.appendingPathComponent("character.usdz"))
            Self.matte(body)
            model = body
            if let idle = body.availableAnimations.first { clips["idle"] = idle }
            for name in ["walk", "run", "jump", "turnL", "turnR", "strafeL", "strafeR", "strafeWalkL", "strafeWalkR"] {
                let url = dir.appendingPathComponent("anim_\(name).usdz")
                if let e = try? Entity.load(contentsOf: url), let a = e.availableAnimations.first { clips[name] = a }
            }
        } catch { failed = true; loadError = String(describing: error) }
        if model != nil && clips["idle"] == nil { loadError = "대기 동작 없음 (애니메이션 \(model?.availableAnimations.count ?? 0)개)" }
    }
    /// v1.32: the exported PBR read as chrome on device (metallic ≈ 1). Force a skin/cloth look:
    /// keep the base-colour texture, metallic 0, high roughness, no clearcoat.
    private static func matte(_ e: Entity) {
        if var model = e.components[ModelComponent.self] {
            model.materials = model.materials.map { m -> RealityKit.Material in
                if var pbr = m as? PhysicallyBasedMaterial {
                    pbr.metallic = .init(floatLiteral: 0)
                    pbr.roughness = .init(floatLiteral: 0.85)
                    pbr.specular = .init(floatLiteral: 0.2)
                    pbr.clearcoat = .init(floatLiteral: 0)
                    pbr.blending = .opaque          // opacity was wired to the colour map
                    pbr.normal = .init(texture: nil) // normal map was over-scaled (2×) → wavy chrome streaks
                    return pbr
                }
                return m
            }
            e.components.set(model)
        }
        for c in e.children { matte(c) }
    }
    var available: Bool { model != nil && clips["idle"] != nil }
}

@MainActor
struct Character3DView: UIViewRepresentable {
    var speedKmh: Double
    var clipOverride: String? = nil
    var interactive = true
    var yaw: Float = 0.35

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> ARView {
        let v = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        v.environment.background = .color(.clear); v.backgroundColor = .clear; v.isOpaque = false
        context.coordinator.attach(v, yaw: yaw)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1; v.addGestureRecognizer(pan)
        let dbl = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.reset(_:)))
        dbl.numberOfTapsRequired = 2; v.addGestureRecognizer(dbl)
        return v
    }
    func updateUIView(_ v: ARView, context: Context) {
        v.isUserInteractionEnabled = interactive
        context.coordinator.update(speed: speedKmh, override: clipOverride)
    }
    static func dismantleUIView(_ v: ARView, coordinator: Coordinator) { coordinator.detach() }

    @MainActor
    final class Coordinator: NSObject {
        private weak var view: ARView?
        private let anchor = AnchorEntity(world: .zero)
        private let camera = PerspectiveCamera()
        private var body: Entity?
        private var current = ""
        private var controller: AnimationPlaybackController?
        private var yaw: Float = 0.35, baseYaw: Float = 0.35, pitch: Float = 0.12

        func attach(_ v: ARView, yaw initial: Float) {
            view = v; yaw = initial; baseYaw = initial
            // Each view gets its own clone so the chat sheet and the dashboard never steal the same entity.
            if let m = CharacterRig.shared.model { let c = m.clone(recursive: true); body = c; anchor.addChild(c) }
            camera.camera.fieldOfViewInDegrees = 30
            anchor.addChild(camera)
            let key = DirectionalLight(); key.light.intensity = 2600; key.look(at: [0, 0.6, 0], from: [1.5, 2.5, 2.5], relativeTo: nil); anchor.addChild(key)
            let fill = DirectionalLight(); fill.light.intensity = 1100; fill.light.color = UIColor(red: 0.85, green: 0.9, blue: 1, alpha: 1)
            fill.look(at: [0, 0.6, 0], from: [-2, 1.5, -1.5], relativeTo: nil); anchor.addChild(fill)
            v.scene.addAnchor(anchor)
            placeCamera()
        }
        func detach() { controller?.stop(); controller = nil; current = ""; view?.scene.anchors.removeAll() }

        private func placeCamera() {
            let target = SIMD3<Float>(0, 0.5, 0), dist: Float = 2.4
            let pos = target + SIMD3(dist * sin(yaw) * cos(pitch), dist * sin(pitch), dist * cos(yaw) * cos(pitch))
            camera.look(at: target, from: pos, relativeTo: nil)
        }
        @objc func pan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view); g.setTranslation(.zero, in: g.view)
            yaw -= Float(t.x) * 0.012
            pitch = min(0.9, max(-0.2, pitch + Float(t.y) * 0.006))
            placeCamera()
        }
        @objc func reset(_ g: UITapGestureRecognizer) { yaw = baseYaw; pitch = 0.12; placeCamera() }

        func update(speed: Double, override: String?) {
            let rig = CharacterRig.shared
            guard let model = body, speed.isFinite else { return }
            let name = override ?? (speed < 3 ? "idle" : speed < 20 ? "walk" : "run")
            let rate: Float = name == "run" ? Float(min(1.5, max(0.8, speed / 60))) : name == "walk" ? Float(min(1.3, max(0.7, speed / 10))) : 1
            if name != current, let clip = rig.clips[name] ?? rig.clips["idle"] {
                current = name
                controller = model.playAnimation(clip.repeat(), transitionDuration: 0.45, startsPaused: false)
            }
            controller?.speed = rate
        }
    }
}
