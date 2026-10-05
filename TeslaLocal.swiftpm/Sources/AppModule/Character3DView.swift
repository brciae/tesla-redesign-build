import SwiftUI
import RealityKit
import UIKit
import Combine
import Metal

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
        CharacterOption(id: "c346796a2", name: "흑발 셔츠", folder: "c_346796a2"),
        CharacterOption(id: "r4d5c4915", name: "흰색 휴머노이드 로봇", folder: "r_4d5c4915", robot: true),
        CharacterOption(id: "raa13fc50", name: "스텔스 로봇", folder: "r_aa13fc50", robot: true),
        CharacterOption(id: "rfd33e359", name: "아머 로봇", folder: "r_fd33e359", robot: true),
    ]
    /// v1.41: an id that is no longer in the catalog (the 1.38 Tripo models were removed) falls back to 유엘.
    static var selectedID: String { selectedID(.dashboard) }
    /// v1.48: the dashboard (running theme) and the floating helper each keep their own character.
    static func selectedID(_ slot: CharacterSlot) -> String {
        let d = UserDefaults.standard
        let id = d.string(forKey: slot.idKey) ?? (slot == .floating ? d.string(forKey: CharacterSlot.dashboard.idKey) : nil) ?? "yl"
        return all.contains { $0.id == id } ? id : "yl"
    }
    var thumbnail: UIImage? {
        guard let dir = Bundle.main.url(forResource: "character", withExtension: nil) else { return nil }
        return UIImage(contentsOfFile: dir.appendingPathComponent("thumb_\(id).png").path)
    }
}

/// v1.43: surface finish chosen in 메뉴 → 캐릭터, applied to every character view (holo also flickers).
enum CharacterFinish: String, CaseIterable, Identifiable {
    case auto, matte, metal, gold, holo
    var id: String { rawValue }
    var title: String {
        switch self { case .auto: return "기본"; case .matte: return "무광"; case .metal: return "메탈"; case .gold: return "골드"; case .holo: return "홀로그램" }
    }
    static var selected: CharacterFinish { selected(.dashboard) }
    static func selected(_ slot: CharacterSlot) -> CharacterFinish {
        let d = UserDefaults.standard
        return CharacterFinish(rawValue: d.string(forKey: slot.finishKey) ?? (slot == .floating ? d.string(forKey: CharacterSlot.dashboard.finishKey) : nil) ?? "") ?? .auto
    }
    /// v1.46: Metal surface shader (HologramShader.metal) — rim glow, scanlines, sweep band, glitch slices.
    @MainActor static let holoShader: CustomMaterial.SurfaceShader? = {
        guard let device = MTLCreateSystemDefaultDevice(), let library = device.makeDefaultLibrary() else { return nil }
        return CustomMaterial.SurfaceShader(named: "hologramSurface", in: library)
    }()
    @MainActor static func apply(_ f: CharacterFinish, to e: Entity) {
        guard f != .auto else { return }
        if var model = e.components[ModelComponent.self] {
            model.materials = model.materials.map { m -> RealityKit.Material in
                guard var p = m as? PhysicallyBasedMaterial else { return m }
                switch f {
                case .holo:
                    if let shader = holoShader, var c = try? CustomMaterial(surfaceShader: shader, lightingModel: .unlit) {
                        c.baseColor = .init(tint: .white, texture: p.baseColor.texture.map { CustomMaterial.Texture($0.resource) })
                        c.blending = .transparent(opacity: .init(floatLiteral: 1))
                        c.custom.value = [10, 0, 0, 0]   // v1.53: fully revealed unless a spawn animation runs
                        return c
                    }
                    var u = UnlitMaterial()
                    u.color = .init(tint: UIColor(red: 0.35, green: 0.95, blue: 1, alpha: 1), texture: p.baseColor.texture)
                    u.blending = .transparent(opacity: .init(floatLiteral: 0.55))
                    return u
                case .matte: p.metallic = .init(floatLiteral: 0); p.roughness = .init(floatLiteral: 0.92)
                case .metal: p.metallic = .init(floatLiteral: 0.95); p.roughness = .init(floatLiteral: 0.22); p.baseColor.tint = UIColor(white: 0.88, alpha: 1)
                case .gold: p.metallic = .init(floatLiteral: 1); p.roughness = .init(floatLiteral: 0.28); p.baseColor.tint = UIColor(red: 1, green: 0.8, blue: 0.4, alpha: 1)
                case .auto: break
                }
                return p
            }
            e.components.set(model)
        }
        for c in e.children { apply(f, to: c) }
    }

    /// v1.48: hologram projector under the feet — glowing pad, light column and rotating rings.
    @MainActor static func addProjector(to root: Entity) {
        let pad = Entity(); pad.name = "holoProjector"
        func disc(_ size: Float, _ image: CGImage?, y: Float, name: String = "") -> ModelEntity {
            var m = UnlitMaterial()
            if let image, let tex = try? TextureResource.generate(from: image, options: .init(semantic: .color)) {
                m.color = .init(tint: .white, texture: .init(tex))
            }
            m.blending = .transparent(opacity: .init(floatLiteral: 1))
            let e = ModelEntity(mesh: .generatePlane(width: size, depth: size), materials: [m])
            e.position.y = y; e.name = name; return e
        }
        pad.addChild(disc(0.62, radial(inner: 0.0, outer: 0.5, rim: true), y: 0.002))
        for (i, r) in [(0, 0.36), (1, 0.48)] { pad.addChild(disc(Float(r) * 2, ring(dashes: i == 0 ? 6 : 10), y: 0.004 + Float(i) * 0.002, name: "holoRing\(i)")) }
        // v1.53: spawn beam (shoots up from the pad), scan ring that rides the materialise front,
        // and matrix-style falling code columns around/behind the figure. The old light column and
        // orbiting symbols are gone (the column read as a white bar through the body).
        var beamM = UnlitMaterial(color: UIColor(red: 0.7, green: 1, blue: 0.97, alpha: 1))
        beamM.blending = .transparent(opacity: .init(floatLiteral: 0.85))
        let beam = ModelEntity(mesh: .generateBox(width: 0.018, height: 1, depth: 0.018), materials: [beamM])
        beam.name = "holoBeam"; beam.isEnabled = false
        pad.addChild(beam)
        let scanRing = disc(0.62, ring(dashes: 1), y: 0, name: "holoScan"); scanRing.isEnabled = false
        pad.addChild(scanRing)
        let rain = Entity(); rain.name = "holoRain"
        let textures = (0..<6).compactMap { k in rainColumn(seed: k).flatMap { try? TextureResource.generate(from: $0, options: .init(semantic: .color)) } }
        if !textures.isEmpty {
            for i in 0..<22 {
                var m = UnlitMaterial()
                m.color = .init(tint: .white, texture: .init(textures[i % textures.count]))
                m.blending = .transparent(opacity: .init(floatLiteral: 1))
                let hStep: Float = Float((i * 53) % 7)
                let h: Float = 0.9 + hStep * 0.12
                let e = ModelEntity(mesh: .generatePlane(width: 0.075, height: h), materials: [m])
                let side: Float = i % 2 == 0 ? -1 : 1
                let behind: Bool = i % 3 != 0
                let fx: Float = Float((i * 37) % 10) / 10
                let fx2: Float = Float((i * 29) % 10) / 10
                let fz: Float = Float((i * 17) % 10) / 10
                let fz2: Float = Float((i * 13) % 10) / 10
                let spread: Float = behind ? 0.08 + fx * 0.85 : 0.42 + fx2 * 0.45
                let x: Float = side * spread
                let z: Float = behind ? -0.35 - fz * 0.7 : 0.05 + fz2 * 0.2
                e.position = [x, 0, z]
                e.name = "rain\(i)"
                rain.addChild(e)
            }
        }
        pad.addChild(rain)
        root.addChild(pad)
    }

    /// Sets the materialise height on every hologram material under `e` (metres, world space).
    @MainActor static func setReveal(_ e: Entity, _ height: Float) {
        if var model = e.components[ModelComponent.self] {
            var changed = false
            model.materials = model.materials.map { m in
                guard var c = m as? CustomMaterial else { return m }
                c.custom.value = [height, 0, 0, 0]; changed = true; return c
            }
            if changed { e.components.set(model) }
        }
        for c in e.children { setReveal(c, height) }
    }

    /// v1.53: whole hologram timeline. `age` = seconds since the character appeared.
    /// 0–0.35 s beam shoots up · 0.35–1.9 s body materialises bottom→top with a scan ring · then idle.
    @MainActor static func animateHolo(pad: Entity, body: Entity?, age: Double, clock: Double) {
        let top: Float = 1.45
        if let beam = pad.findEntity(named: "holoBeam") {
            let shoot = Float(min(1, age / 0.35))
            let fade = Float(max(0, 1 - max(0, age - 1.9) / 0.5))
            beam.isEnabled = fade > 0.01
            if beam.isEnabled {
                let len: Float = max(0.001, top * shoot)
                let widen: Float = 1 + 2.5 * (1 - fade)
                beam.scale = SIMD3<Float>(widen, len, widen)
                beam.position.y = len / 2
                let pulse: Float = 0.75 + 0.25 * Float(sin(clock * 40))
                if #available(iOS 18.0, *) { beam.components.set(OpacityComponent(opacity: fade * pulse)) }
            }
        }
        let progress = Float(min(1, max(0, (age - 0.35) / 1.55)))
        let front = -0.05 + progress * (top + 0.15)
        if let scan = pad.findEntity(named: "holoScan") {
            scan.isEnabled = progress > 0 && progress < 1
            scan.position.y = front
            scan.orientation = simd_quatf(angle: Float(clock) * 3, axis: [0, 1, 0])
        }
        if let body, age < 2.3 { setReveal(body, age < 0.35 ? -1 : (progress >= 1 ? 10 : front)) }
        for (i, name) in ["holoRing0", "holoRing1"].enumerated() {
            pad.findEntity(named: name)?.orientation = simd_quatf(angle: Float(clock) * (i == 0 ? 0.8 : -0.5), axis: [0, 1, 0])
        }
        // rain starts once the beam fires, falls at varied speeds and wraps
        if let rain = pad.findEntity(named: "holoRain") {
            rain.isEnabled = age > 0.2
            for (i, e) in rain.children.enumerated() {
                let speed: Double = 0.35 + Double((i * 41) % 10) / 10 * 0.55
                let span: Double = 3.2
                let offset: Double = Double((i * 71) % 100) / 100 * span
                let y: Double = 2.2 - (clock * speed + offset).truncatingRemainder(dividingBy: span)
                e.position.y = Float(y)
            }
        }
    }
    private static func bitmap(_ size: Int, _ draw: (CGContext, CGFloat) -> Void) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(ctx, CGFloat(size)); return ctx.makeImage()
    }
    private static let cyan = UIColor(red: 0.3, green: 0.95, blue: 1, alpha: 1)
    private static func radial(inner: CGFloat, outer: CGFloat, rim: Bool) -> CGImage? {
        bitmap(256) { ctx, s in
            let colors = [cyan.withAlphaComponent(0.55).cgColor, cyan.withAlphaComponent(0.18).cgColor, cyan.withAlphaComponent(0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.7, 1]) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: s / 2, y: s / 2), startRadius: 0, endCenter: CGPoint(x: s / 2, y: s / 2), endRadius: s / 2, options: [])
            }
            if rim { ctx.setStrokeColor(cyan.withAlphaComponent(0.9).cgColor); ctx.setLineWidth(3); ctx.strokeEllipse(in: CGRect(x: 6, y: 6, width: s - 12, height: s - 12)) }
        }
    }
    private static func ring(dashes: Int) -> CGImage? {
        bitmap(256) { ctx, s in
            ctx.setStrokeColor(cyan.withAlphaComponent(0.85).cgColor); ctx.setLineWidth(4)
            ctx.setLineDash(phase: 0, lengths: [s * 3.0 / CGFloat(dashes), s * 1.2 / CGFloat(dashes)])
            ctx.strokeEllipse(in: CGRect(x: 4, y: 4, width: s - 8, height: s - 8))
        }
    }
    private static func drawRainGlyph(k: Int, count: Int, seed: Int, chars: [Character], width w: CGFloat, step: CGFloat) {
        let t: CGFloat = CGFloat(k) / CGFloat(max(1, count - 1))     // 0 top … 1 bottom (leading glyph)
        let index: Int = (seed * 31 + k * 17 + k * k * 7) % chars.count
        let lead: Bool = k == count - 1
        let fadeAlpha: CGFloat = 0.08 + 0.7 * pow(t, 1.6)
        let color: UIColor = lead ? UIColor(white: 1, alpha: 0.95) : UIColor(red: 0.25, green: 1, blue: 0.85, alpha: fadeAlpha)
        let font: UIFont = UIFont.monospacedSystemFont(ofSize: 30, weight: lead ? .bold : .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str = NSAttributedString(string: String(chars[index]), attributes: attrs)
        let sz: CGSize = str.size()
        str.draw(at: CGPoint(x: (w - sz.width) / 2, y: CGFloat(k) * step))
    }
    /// One falling code column: glyphs top→bottom, brightest (white) at the leading bottom glyph, fading upward.
    private static func rainColumn(seed: Int) -> CGImage? {
        let chars = Array("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉ0123456789ABCDEFXZ=+*<>:")
        let w: CGFloat = 48, h: CGFloat = 768, step: CGFloat = 38
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let r = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)
        let count = Int(h / step)
        let img = r.image { (_: UIGraphicsImageRendererContext) -> Void in
            for k in 0..<count { drawRainGlyph(k: k, count: count, seed: seed, chars: chars, width: w, step: step) }
        }
        return img.cgImage
    }
}

/// Lets this file (also compiled into the interface probe) open the app-only Typecast picker.
enum CharacterHooks {
    @MainActor static var floatingVoicePicker: (() -> AnyView)?
}

enum CharacterSlot: String, CaseIterable, Identifiable {
    case dashboard, floating
    var id: String { rawValue }
    var title: String { self == .dashboard ? "대시보드" : "떠있는 캐릭터" }
    var idKey: String { self == .dashboard ? "character.id" : "characterFloat.id" }
    var finishKey: String { self == .dashboard ? "character.finish" : "characterFloat.finish" }
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
    var slot: CharacterSlot = .dashboard
    @AppStorage("character.id") private var characterID = "yl" // re-renders every character view on change
    @AppStorage("character.finish") private var finish = "auto"
    @AppStorage("characterFloat.id") private var floatID = ""
    @AppStorage("characterFloat.finish") private var floatFinish = ""

    func makeCoordinator() -> Coordinator { let c = Coordinator(); c.slot = slot; return c }
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
        var slot: CharacterSlot = .dashboard
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
            if !on { body?.transform = base }
        }
        private var loadedFinish = CharacterFinish.auto
        private var projector: Entity?
        private var glitch = 0.0
        private var holoStart = 0.0
        // v1.55: robots fly (Iron-Man style) instead of walking/running: hover when parked, lift off and
        // lean into the direction of travel as speed rises, with flickering foot thrusters.
        private var isRobot = false
        private var flight: Float = 0, flightTarget: Float = 0
        private var thrusters: [ModelEntity] = []
        /// Breathing bob + slow body sway so the character never looks frozen, and a fidget every 6–12 s.
        private func step(_ dt: Double) {
            clock += dt
            guard let b = body else { return }
            if loadedFinish == .holo, let p = projector?.children.first {
                CharacterFinish.animateHolo(pad: p, body: b, age: clock - holoStart, clock: clock)
            }
            if loadedFinish == .holo, CharacterFinish.holoShader == nil {
                // fallback hologram (no shader): soft flicker with an occasional short dropout
                if glitch <= 0, Double.random(in: 0...1) < dt * 0.35 { glitch = 0.12 }
                glitch -= dt
                let o = glitch > 0 ? 0.35 : 0.82 + 0.1 * sin(clock * 9) + 0.05 * sin(clock * 23)
                if #available(iOS 18.0, *) { b.components.set(OpacityComponent(opacity: Float(o))) }
                else { b.isEnabled = glitch <= 0 } // iOS 17: dropout blink only
            }
            if isRobot { robotStep(b, dt); return }
            guard ambient else { return }
            let t = Float(clock)
            b.position = base.translation + [0, 0.012 * sin(t * 2.1), 0]
            b.orientation = simd_quatf(angle: 0.18 * sin(t * 0.35), axis: [0, 1, 0]) * simd_quatf(angle: 0.025 * sin(t * 0.9), axis: [0, 0, 1]) * base.rotation
            if clock >= nextFidget {
                nextFidget = clock + Double.random(in: 6...12)
                if !reacting { react(["lookaround", "think", "happy", "nod", "wave", "point", "lookaround"].randomElement()!) }
            }
        }

        private func robotStep(_ b: Entity, _ dt: Double) {
            let k: Float = Float(min(1, dt * 1.6))
            flight += (flightTarget - flight) * k
            let t: Float = Float(clock)
            let hover: Float = 0.06 + 0.02 * sin(t * 2.6)
            let lift: Float = hover + 0.34 * flight + 0.015 * flight * sin(t * 7.0)
            b.position = base.translation + SIMD3<Float>(0, lift, 0)
            // lean forward toward travel (+Z faces the camera side), slight banking sway while flying
            let lean = simd_quatf(angle: 1.1 * flight, axis: [1, 0, 0])
            let bank = simd_quatf(angle: 0.12 * flight * sin(t * 0.8), axis: [0, 0, 1])
            let idleTurn = simd_quatf(angle: (1 - flight) * 0.15 * sin(t * 0.3), axis: [0, 1, 0])
            b.orientation = idleTurn * lean * bank * base.rotation
            let jitter: Float = 0.85 + 0.15 * Float(sin(clock * 53)) * Float(sin(clock * 31))
            let power: Float = 0.35 + 0.65 * flight
            for th in thrusters {
                th.scale = SIMD3<Float>(1, max(0.05, power * jitter), 1)
                if #available(iOS 18.0, *) { th.components.set(OpacityComponent(opacity: 0.55 + 0.45 * power)) }
            }
            if ambient, flight < 0.05, clock >= nextFidget {
                nextFidget = clock + Double.random(in: 7...13)
                if !reacting { react(["lookaround", "point", "nod", "wave"].randomElement()!) }
            }
        }
        /// Two thruster flames under the feet (box flame + glow disc), children of the body root.
        private func addThrusters(to b: Entity) {
            thrusters.removeAll()
            let bounds = b.visualBounds(relativeTo: b)
            let width: Float = max(0.1, bounds.extents.x)
            var flame = UnlitMaterial(color: UIColor(red: 1, green: 0.75, blue: 0.35, alpha: 1))
            flame.blending = .transparent(opacity: .init(floatLiteral: 0.75))
            var core = UnlitMaterial(color: UIColor(red: 0.75, green: 0.95, blue: 1, alpha: 1))
            core.blending = .transparent(opacity: .init(floatLiteral: 0.9))
            for side: Float in [-1, 1] {
                let holder = ModelEntity()
                holder.position = SIMD3<Float>(bounds.center.x + side * width * 0.14, bounds.min.y + 0.01, bounds.center.z)
                let outer = ModelEntity(mesh: .generateBox(width: 0.045, height: 0.22, depth: 0.045, cornerRadius: 0.02), materials: [flame])
                outer.position.y = -0.11
                let inner = ModelEntity(mesh: .generateBox(width: 0.02, height: 0.14, depth: 0.02, cornerRadius: 0.01), materials: [core])
                inner.position.y = -0.07
                holder.addChild(outer); holder.addChild(inner)
                b.addChild(holder)
                thrusters.append(holder)
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
            tick = v.scene.subscribe(to: SceneEvents.Update.self) { [weak self] e in
                MainActor.assumeIsolated { self?.step(e.deltaTime) }
            }
            observer = NotificationCenter.default.addObserver(forName: CharacterReact.note, object: nil, queue: .main) { [weak self] n in
                guard let clip = n.object as? String else { return }
                MainActor.assumeIsolated { self?.react(clip) }
            }
        }
        /// Clone the selected character's body (each view owns its clone so screens never steal it).
        func loadBody() {
            body?.removeFromParent(); body = nil
            let rig = CharacterRig.rig(CharacterOption.selectedID(slot)); loadedID = rig.id
            loadedFinish = CharacterFinish.selected(slot)
            projector?.removeFromParent(); projector = nil
            if let m = rig.model { let c = m.clone(recursive: true); CharacterFinish.apply(loadedFinish, to: c); body = c; base = c.transform; anchor.addChild(c) }
            isRobot = CharacterOption.all.first(where: { $0.id == rig.id })?.robot == true
            flight = 0; flightTarget = 0; thrusters.removeAll()
            if isRobot, let body { addThrusters(to: body) }
            if loadedFinish == .holo {
                let holder = Entity(); CharacterFinish.addProjector(to: holder); anchor.addChild(holder); projector = holder
                holoStart = clock
                if let body { CharacterFinish.setReveal(body, -1) }   // hidden until the beam fires
            }
            current = ""; reacting = false
        }
        func detach() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            tick?.cancel(); tick = nil
            controller?.stop(); controller = nil; current = ""; view?.scene.anchors.removeAll()
        }
        /// v1.36: one-shot gesture (wave, nod, shake, clap…) then back to the speed/state loop.
        func react(_ name: String) {
            guard let model = body, let clip = CharacterRig.rig(loadedID).clips[name], !reacting else { return }
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
            let rig = CharacterRig.rig(CharacterOption.selectedID(slot))
            lastSpeed = speed; lastOverride = override
            if loadedID != CharacterOption.selectedID(slot) || loadedFinish != CharacterFinish.selected(slot) { loadBody() }
            guard let model = body, speed.isFinite, !reacting else { return }
            // robots: no walk/run cycle — they hold the idle stance and fly (see robotStep)
            flightTarget = isRobot && override == nil ? Float(min(1, max(0, (speed - 3) / 70))) : 0
            let name = override ?? (isRobot || speed < 3 ? "idle" : speed < 20 ? "walk" : "run")
            let rate: Float = name == "run" ? Float(min(1.5, max(0.8, speed / 60))) : name == "walk" ? Float(min(1.3, max(0.7, speed / 10))) : (isRobot ? max(0.4, 1 - 0.6 * flightTarget) : 1)
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
    @State private var slot: CharacterSlot = .dashboard
    @State private var previewID: String = CharacterOption.selectedID
    @AppStorage("character.id") private var dashID = "yl"
    @AppStorage("character.finish") private var dashFinish = "auto"
    @AppStorage("characterFloat.id") private var floatID = ""
    @AppStorage("characterFloat.finish") private var floatFinish = ""
    @AppStorage("characterChat.enabled") private var floatEnabled = true
    @AppStorage("characterFloat.scale") private var floatScale = 1.0
    private var characterID: String {
        get { CharacterOption.selectedID(slot) }
        nonmutating set { if slot == .dashboard { dashID = newValue } else { floatID = newValue } }
    }
    private var finishBinding: Binding<String> {
        Binding(get: { CharacterFinish.selected(slot).rawValue },
                set: { if slot == .dashboard { dashFinish = $0 } else { floatFinish = $0 } })
    }
    private var finish: String { finishBinding.wrappedValue }
    var body: some View {
        List {
            Section {
                // v1.48: dashboard (running theme) and the floating helper are set separately.
                Picker("설정 대상", selection: $slot) {
                    ForEach(CharacterSlot.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                .onChange(of: slot) { _, s in previewID = CharacterOption.selectedID(s) }
                Picker("질감", selection: finishBinding) {
                    ForEach(CharacterFinish.allCases) { Text($0.title).tag($0.rawValue) }
                }.pickerStyle(.segmented)
                ZStack(alignment: .bottom) {
                    CharacterPreview(id: previewID, finish: finish)
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
                // v1.55: this page is only about how characters look; every voice lives in 음성·내비 안내.
                if slot == .floating {
                    Toggle("화면에 떠있는 캐릭터 표시", isOn: $floatEnabled)
                    HStack {
                        Text("크기")
                        Slider(value: $floatScale, in: 0.6...2.2, step: 0.1)
                        Text("\(Int((floatScale * 100).rounded()))%").monospacedDigit().frame(minWidth: 52, alignment: .trailing)
                    }
                    Button("기본 크기로") { floatScale = 1.0 }
                }
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
    var finish = "auto"
    func makeCoordinator() -> Coord { Coord() }
    func makeUIView(context: Context) -> ARView {
        let v = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        v.environment.background = .color(.clear); v.backgroundColor = .clear; v.isOpaque = false
        context.coordinator.setup(v)
        v.addGestureRecognizer(UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coord.pan(_:))))
        let dbl = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coord.reset)); dbl.numberOfTapsRequired = 2
        v.addGestureRecognizer(dbl)
        context.coordinator.show(id, finish: finish)
        return v
    }
    func updateUIView(_ v: ARView, context: Context) { context.coordinator.show(id, finish: finish) }
    static func dismantleUIView(_ v: ARView, coordinator: Coord) { coordinator.tick?.cancel(); v.scene.anchors.removeAll() }
    @MainActor final class Coord: NSObject {
        let anchor = AnchorEntity(world: .zero), turntable = Entity(), camera = PerspectiveCamera()
        var shown = ""
        weak var view: ARView?
        var tick: Cancellable?
        var clock = 0.0, holoStart = 0.0
        var holoPad: Entity?
        weak var holoBody: Entity?
        func setup(_ v: ARView) {
            view = v
            tick = v.scene.subscribe(to: SceneEvents.Update.self) { [weak self] e in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.clock += e.deltaTime
                    if let pad = self.holoPad {
                        // the pad stays put while the figure turns; keep the reveal in sync with the figure
                        CharacterFinish.animateHolo(pad: pad, body: self.holoBody, age: self.clock - self.holoStart, clock: self.clock)
                    }
                }
            }
            anchor.addChild(turntable)
            camera.camera.fieldOfViewInDegrees = 30
            camera.look(at: [0, 0.5, 0], from: [0, 0.75, 2.4], relativeTo: nil); anchor.addChild(camera)
            let key = DirectionalLight(); key.light.intensity = 2600; key.look(at: [0, 0.6, 0], from: [1.5, 2.5, 2.5], relativeTo: nil); anchor.addChild(key)
            let fill = DirectionalLight(); fill.light.intensity = 1100; fill.look(at: [0, 0.6, 0], from: [-2, 1.5, -1.5], relativeTo: nil); anchor.addChild(fill)
            v.scene.addAnchor(anchor)
        }
        func show(_ id: String, finish: String = "auto") {
            guard id + finish != shown else { return }
            shown = id + finish
            turntable.children.removeAll()
            let rig = CharacterRig.rig(id)
            guard let m = rig.model else { return }
            let f = CharacterFinish(rawValue: finish) ?? .auto
            let c = m.clone(recursive: true); CharacterFinish.apply(f, to: c); turntable.addChild(c)
            holoPad?.removeFromParent(); holoPad = nil; holoBody = nil
            // v1.53: dark stage for the hologram so it reads like Tripo's viewer; clear for the others
            view?.environment.background = .color(f == .holo ? UIColor(red: 0.02, green: 0.07, blue: 0.075, alpha: 1) : .clear)
            if f == .holo {
                let holder = Entity(); CharacterFinish.addProjector(to: holder); anchor.addChild(holder)
                holoPad = holder.children.first; holoBody = c; holoStart = clock
                CharacterFinish.setReveal(c, -1)
            }
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
