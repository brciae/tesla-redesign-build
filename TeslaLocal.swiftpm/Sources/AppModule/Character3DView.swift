import SwiftUI
import RealityKit
import UIKit
import Combine

/// v1.28: rigged 3D character (Tripo mesh + Mixamo motion capture, retargeted, root motion removed).
/// Clips cross-fade by vehicle speed, so motion is continuous; drag to orbit and view from any side.
/// v1.37: selectable characters. Each lives in Resources/character/<folder> with character.usdz plus
/// anim_<clip>.usdz files retargeted to its own skeleton. "" is the original character at the root.
struct CharacterOption: Identifiable, Hashable {
    let id: String, name: String, folder: String
    /// v1.42: robots keep a satin-metal finish instead of the skin/cloth matte look.
    var robot = false
    static let all: [CharacterOption] = [
        CharacterOption(id: "yl", name: "유엘 (기본)", folder: ""),
        CharacterOption(id: "wolf", name: "늑대 소녀", folder: "c_wolf"),
        CharacterOption(id: "r4d5c4915", name: "흰색 휴머노이드 로봇", folder: "r_4d5c4915", robot: true),
        CharacterOption(id: "raa13fc50", name: "스텔스 로봇", folder: "r_aa13fc50", robot: true),
        CharacterOption(id: "rfd33e359", name: "아머 로봇", folder: "r_fd33e359", robot: true),
    ]
    /// v1.41: an id that is no longer in the catalog (the 1.38 Tripo models were removed) falls back to 유엘.
    static var selectedID: String {
        let id = UserDefaults.standard.string(forKey: "character.id") ?? "yl"
        return all.contains { $0.id == id } ? id : "yl"
    }
    var thumbnail: UIImage? {
        guard let dir = Bundle.main.url(forResource: "character", withExtension: nil) else { return nil }
        return UIImage(contentsOfFile: dir.appendingPathComponent("thumb_\(id).png").path)
    }
}

@MainActor
final class CharacterRig {
    private static var cache: [String: CharacterRig] = [:]
    /// The rig for the character chosen in 설정 → 캐릭터 (loaded once, then cached).
    static var shared: CharacterRig { rig(CharacterOption.selectedID) }
    static func rig(_ id: String) -> CharacterRig {
        if let r = cache[id] { return r }
        let option = CharacterOption.all.first { $0.id == id } ?? CharacterOption.all[0]
        let r = CharacterRig(folder: option.folder, robot: option.robot); r.id = option.id
        cache[option.id] = r
        return r
    }
    private(set) var id = "yl"
    private(set) var model: Entity?
    private(set) var clips: [String: AnimationResource] = [:]
    private(set) var failed = false
    private(set) var loadError: String?
    private init(folder: String, robot: Bool = false) {
        guard var dir = Bundle.main.url(forResource: "character", withExtension: nil) else { failed = true; loadError = "character 폴더 없음"; return }
        if !folder.isEmpty { dir = dir.appendingPathComponent(folder, isDirectory: true) }
        do {
            let body = try Entity.load(contentsOf: dir.appendingPathComponent("character.usdz"))
            Self.matte(body, robot: robot)
            model = body
            // v1.42: anim_idle.usdz is the full loop; character.usdz may carry only a 2-frame pose.
            if let e = try? Entity.load(contentsOf: dir.appendingPathComponent("anim_idle.usdz")), let a = e.availableAnimations.first { clips["idle"] = a }
            else if let idle = body.availableAnimations.first { clips["idle"] = idle }
            for name in ["walk", "run", "jump", "turnL", "turnR", "strafeL", "strafeR", "strafeWalkL", "strafeWalkR",
                         "wave", "talk", "think", "nod", "shake", "happy", "clap", "point", "lookaround", "sit"] {
                let url = dir.appendingPathComponent("anim_\(name).usdz")
                if let e = try? Entity.load(contentsOf: url), let a = e.availableAnimations.first { clips[name] = a }
            }
        } catch { failed = true; loadError = String(describing: error) }
        if model != nil && clips["idle"] == nil { loadError = "대기 동작 없음 (애니메이션 \(model?.availableAnimations.count ?? 0)개)" }
    }
    /// v1.32: the exported PBR read as chrome on device (metallic ≈ 1). Force a skin/cloth look:
    /// keep the base-colour texture, metallic 0, high roughness, no clearcoat.
    private static func matte(_ e: Entity, robot: Bool = false) {
        if var model = e.components[ModelComponent.self] {
            model.materials = model.materials.map { m -> RealityKit.Material in
                if var pbr = m as? PhysicallyBasedMaterial {
                    pbr.metallic = .init(floatLiteral: robot ? 0.55 : 0)
                    pbr.roughness = .init(floatLiteral: robot ? 0.38 : 0.85)
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
        for c in e.children { matte(c, robot: robot) }
    }
    var available: Bool { model != nil && clips["idle"] != nil }
}

@MainActor
struct Character3DView: UIViewRepresentable {
    var speedKmh: Double
    var clipOverride: String? = nil
    var interactive = true
    var yaw: Float = 0.35
    /// v1.40: idle life — gentle sway/breathing plus a random gesture every few seconds.
    var ambient = false
    @AppStorage("character.id") private var characterID = "yl" // re-renders every character view on change

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
        context.coordinator.setAmbient(ambient)
        context.coordinator.update(speed: speedKmh, override: clipOverride)
    }
    static func dismantleUIView(_ v: ARView, coordinator: Coordinator) { coordinator.detach() }

    @MainActor
    final class Coordinator: NSObject {
        private weak var view: ARView?
        private let anchor = AnchorEntity(world: .zero)
        private let camera = PerspectiveCamera()
        private var body: Entity?
        private var loadedID = ""
        private var current = ""
        private var controller: AnimationPlaybackController?
        private var yaw: Float = 0.35, baseYaw: Float = 0.35, pitch: Float = 0.12
        private var reacting = false
        private var lastSpeed = 0.0, lastOverride: String?
        private var observer: NSObjectProtocol?
        private var ambient = false
        private var base = Transform.identity
        private var tick: Cancellable?
        private var clock: Double = 0, nextFidget: Double = 4

        func setAmbient(_ on: Bool) {
            guard on != ambient else { return }
            ambient = on
            if on, let v = view {
                tick = v.scene.subscribe(to: SceneEvents.Update.self) { [weak self] e in
                    MainActor.assumeIsolated { self?.step(e.deltaTime) }
                }
            } else { tick?.cancel(); tick = nil; body?.transform = base }
        }
        /// Breathing bob + slow body sway so the character never looks frozen, and a fidget every 6–12 s.
        private func step(_ dt: Double) {
            clock += dt
            guard let b = body else { return }
            let t = Float(clock)
            b.position = base.translation + [0, 0.012 * sin(t * 2.1), 0]
            b.orientation = simd_quatf(angle: 0.18 * sin(t * 0.35), axis: [0, 1, 0]) * simd_quatf(angle: 0.025 * sin(t * 0.9), axis: [0, 0, 1]) * base.rotation
            if clock >= nextFidget {
                nextFidget = clock + Double.random(in: 6...12)
                if !reacting { react(["lookaround", "think", "happy", "nod", "wave", "point", "lookaround"].randomElement()!) }
            }
        }

        func attach(_ v: ARView, yaw initial: Float) {
            view = v; yaw = initial; baseYaw = initial
            // Each view gets its own clone so the chat sheet and the dashboard never steal the same entity.
            loadBody()
            camera.camera.fieldOfViewInDegrees = 30
            anchor.addChild(camera)
            let key = DirectionalLight(); key.light.intensity = 2600; key.look(at: [0, 0.6, 0], from: [1.5, 2.5, 2.5], relativeTo: nil); anchor.addChild(key)
            let fill = DirectionalLight(); fill.light.intensity = 1100; fill.light.color = UIColor(red: 0.85, green: 0.9, blue: 1, alpha: 1)
            fill.look(at: [0, 0.6, 0], from: [-2, 1.5, -1.5], relativeTo: nil); anchor.addChild(fill)
            v.scene.addAnchor(anchor)
            placeCamera()
            observer = NotificationCenter.default.addObserver(forName: CharacterReact.note, object: nil, queue: .main) { [weak self] n in
                guard let clip = n.object as? String else { return }
                MainActor.assumeIsolated { self?.react(clip) }
            }
        }
        /// Clone the selected character's body (each view owns its clone so screens never steal it).
        func loadBody() {
            body?.removeFromParent(); body = nil
            let rig = CharacterRig.shared; loadedID = rig.id
            if let m = rig.model { let c = m.clone(recursive: true); body = c; base = c.transform; anchor.addChild(c) }
            current = ""; reacting = false
        }
        func detach() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            tick?.cancel(); tick = nil
            controller?.stop(); controller = nil; current = ""; view?.scene.anchors.removeAll()
        }
        /// v1.36: one-shot gesture (wave, nod, shake, clap…) then back to the speed/state loop.
        func react(_ name: String) {
            guard let model = body, let clip = CharacterRig.shared.clips[name], !reacting else { return }
            reacting = true
            controller = model.playAnimation(clip, transitionDuration: 0.3, startsPaused: false)
            let length = max(0.8, min(6, clip.definition.duration))
            DispatchQueue.main.asyncAfter(deadline: .now() + length - 0.25) { [weak self] in
                guard let self else { return }
                self.reacting = false; self.current = ""
                self.update(speed: self.lastSpeed, override: self.lastOverride)
            }
        }

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
            lastSpeed = speed; lastOverride = override
            if loadedID != CharacterOption.selectedID { loadBody() }
            guard let model = body, speed.isFinite, !reacting else { return }
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

/// v1.36: app events → character gestures. Any visible character (floating, chat, dashboard) reacts.
enum CharacterReact {
    static let note = Notification.Name("YLCharacterReact")
    static let speech = Notification.Name("YLCharacterSpeech")
    /// v1.37: what the app says out loud also appears as the floating character's speech bubble.
    static func say(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        DispatchQueue.main.async { NotificationCenter.default.post(name: speech, object: t) }
    }
    static func send(_ clip: String) {
        DispatchQueue.main.async { NotificationCenter.default.post(name: note, object: clip) }
    }
}

/// v1.37: 메뉴 → 캐릭터. Preview each character in 3D (drag to turn) and pick the one used everywhere.
struct CharacterSelectView: View {
    @AppStorage("character.id") private var characterID = "yl"
    @State private var previewID: String = CharacterOption.selectedID
    var body: some View {
        List {
            Section {
                ZStack(alignment: .bottom) {
                    CharacterPreview(id: previewID)
                        .frame(height: 320)
                    Text("드래그해서 돌려보기 · 두 번 탭하면 정면").font(.caption2).foregroundStyle(.secondary).padding(.bottom, 6)
                }
                .listRowInsets(EdgeInsets())
                Button {
                    characterID = previewID
                    CharacterReact.send("wave")
                } label: {
                    Label(characterID == previewID ? "사용 중" : "이 캐릭터 사용", systemImage: characterID == previewID ? "checkmark.circle.fill" : "person.crop.circle.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(characterID == previewID)
            }
            Section("캐릭터") {
                ForEach(CharacterOption.all) { option in
                    Button { previewID = option.id } label: {
                        HStack(spacing: 12) {
                            Group {
                                if let img = option.thumbnail { Image(uiImage: img).resizable().scaledToFit() }
                                else { Image(systemName: "person.fill").font(.title2).foregroundStyle(.secondary) }
                            }
                            .frame(width: 44, height: 64)
                            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                            Text(option.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                            Spacer()
                            if characterID == option.id { Text("사용 중").font(.caption.weight(.bold)).foregroundStyle(.green) }
                            else if previewID == option.id { Text("미리보기").font(.caption).foregroundStyle(.blue) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("캐릭터")
    }
}

/// A standalone 3D view of one character (not the selected one), used by the picker.
private struct CharacterPreview: UIViewRepresentable {
    let id: String
    func makeCoordinator() -> Coord { Coord() }
    func makeUIView(context: Context) -> ARView {
        let v = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        v.environment.background = .color(.clear); v.backgroundColor = .clear; v.isOpaque = false
        context.coordinator.setup(v)
        v.addGestureRecognizer(UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coord.pan(_:))))
        let dbl = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coord.reset)); dbl.numberOfTapsRequired = 2
        v.addGestureRecognizer(dbl)
        context.coordinator.show(id)
        return v
    }
    func updateUIView(_ v: ARView, context: Context) { context.coordinator.show(id) }
    static func dismantleUIView(_ v: ARView, coordinator: Coord) { v.scene.anchors.removeAll() }
    @MainActor final class Coord: NSObject {
        let anchor = AnchorEntity(world: .zero), turntable = Entity(), camera = PerspectiveCamera()
        var shown = ""
        func setup(_ v: ARView) {
            anchor.addChild(turntable)
            camera.camera.fieldOfViewInDegrees = 30
            camera.look(at: [0, 0.5, 0], from: [0, 0.75, 2.4], relativeTo: nil); anchor.addChild(camera)
            let key = DirectionalLight(); key.light.intensity = 2600; key.look(at: [0, 0.6, 0], from: [1.5, 2.5, 2.5], relativeTo: nil); anchor.addChild(key)
            let fill = DirectionalLight(); fill.light.intensity = 1100; fill.look(at: [0, 0.6, 0], from: [-2, 1.5, -1.5], relativeTo: nil); anchor.addChild(fill)
            v.scene.addAnchor(anchor)
        }
        func show(_ id: String) {
            guard id != shown else { return }
            shown = id
            turntable.children.removeAll()
            let rig = CharacterRig.rig(id)
            guard let m = rig.model else { return }
            let c = m.clone(recursive: true); turntable.addChild(c)
            if let idle = rig.clips["wave"] ?? rig.clips["idle"] {
                c.playAnimation(idle, transitionDuration: 0, startsPaused: false)
                if let loop = rig.clips["idle"] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + idle.definition.duration) { [weak c] in c?.playAnimation(loop.repeat(), transitionDuration: 0.4, startsPaused: false) }
                }
            }
        }
        @objc func pan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view); g.setTranslation(.zero, in: g.view)
            turntable.orientation = simd_quatf(angle: Float(t.x) * 0.012, axis: [0, 1, 0]) * turntable.orientation
        }
        @objc func reset() { turntable.orientation = simd_quatf(angle: 0, axis: [0, 1, 0]) }
    }
}
