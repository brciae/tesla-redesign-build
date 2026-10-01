import SwiftUI

/// Front-facing running character for the driving dashboard.
/// Frames come from the bundle ("CharacterFrames/<clip>/0000.png" … plus manifest.json) once the
/// character video is processed; until then a procedural stand-in shows the same timing model
/// (idle → walk → jog → run → sprint, lean and bounce growing with speed, ease in/out between gaits).
struct CharacterRunnerView: View {
    let speedKmh: Double
    @State private var clock = RunnerClock()
    private var phase: Double { clock.phase }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { context in
            let s = advance(to: context.date)
            if let frames = CharacterAtlas.shared, let img = frames.frame(for: clock, speed: s, now: context.date) {
                Image(uiImage: img).resizable().interpolation(.high).scaledToFit()
                    .scaleEffect(y: s < 2 ? 1 + 0.006 * sin(context.date.timeIntervalSinceReferenceDate * 2.2) : 1, anchor: .bottom)
            } else {
                Canvas { g, size in draw(g, size: size, speed: s) }
            }
        }
        .accessibilityLabel(speedKmh < 3 ? "캐릭터 대기 중" : "캐릭터 달리는 중")
    }

    /// Integrates the stride phase so cadence changes never jump; speed itself eases toward the car's.
    private func advance(to now: Date) -> Double {
        let c = clock
        let dt = min(0.1, c.last.map { now.timeIntervalSince($0) } ?? 0)
        c.last = now
        c.smoothed += (speedKmh - c.smoothed) * min(1, dt * 2.2)
        let cadence = c.smoothed < 2 ? 0 : 1.1 + min(c.smoothed, 120) / 120 * 1.9 // strides per second
        c.phase = (c.phase + dt * cadence * 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
        return c.smoothed
    }

    private func draw(_ g: GraphicsContext, size: CGSize, speed: Double) {
        let k: Double = min(1, speed / 110)                 // 0 idle … 1 sprint
        let moving = speed >= 2
        let h = size.height * 0.9, cx = size.width / 2
        let groundY = size.height * 0.96
        let breathe: CGFloat = CGFloat(sin(Date().timeIntervalSinceReferenceDate * 2.2) * 0.006) * h
        let bob: CGFloat = moving ? CGFloat(abs(sin(phase)) * (0.015 + 0.05 * k)) * h : breathe
        let lean: Double = moving ? 0.05 + 0.25 * k : 0
        let hipY = groundY - h * 0.47 - bob
        let shoulderY = hipY - h * 0.30
        let swing: Double = moving ? sin(phase) * (0.35 + 0.55 * k) : 0
        let blue = Color(red: 0.12, green: 0.30, blue: 0.75)

        // Shadow grows on landing.
        let sw: CGFloat = h * (0.22 - 0.05 * (bob / (0.065 * h + 0.001)))
        g.fill(Path(ellipseIn: CGRect(x: cx - sw / 2, y: groundY - 6, width: sw, height: 12)), with: .color(.black.opacity(0.22)))

        func limb(from a: CGPoint, angle: Double, length: CGFloat, bend: Double, width: CGFloat, color: Color) {
            let knee = CGPoint(x: a.x + CGFloat(sin(angle)) * length * 0.5, y: a.y + CGFloat(cos(angle)) * length * 0.5)
            let foot = CGPoint(x: knee.x + CGFloat(sin(angle + bend)) * length * 0.5, y: knee.y + CGFloat(cos(angle + bend)) * length * 0.5)
            var p = Path(); p.move(to: a); p.addLine(to: knee); p.addLine(to: foot)
            g.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        let legLen = h * 0.47
        // Front view: legs lift toward the camera, so knee drive shows as shortening + sideways splay.
        for side in [-1.0, 1.0] {
            let s = swing * side
            let hip = CGPoint(x: cx + CGFloat(side) * h * 0.045, y: hipY)
            let lift: Double = max(0, s) * (0.25 + 0.35 * k)
            limb(from: hip, angle: side * 0.04, length: legLen * CGFloat(1 - lift), bend: -side * lift * 0.6, width: h * 0.05, color: Color(white: 0.93))
        }
        // Torso with forward lean (foreshortened in front view).
        let torsoTop = CGPoint(x: cx, y: shoulderY + CGFloat(lean) * h * 0.05)
        var torso = Path(); torso.addRoundedRect(in: CGRect(x: cx - h * 0.075, y: torsoTop.y, width: h * 0.15, height: hipY - torsoTop.y + h * 0.02), cornerSize: CGSize(width: h * 0.03, height: h * 0.03))
        g.fill(torso, with: .color(blue))
        for side in [-1.0, 1.0] {
            let s = -swing * side
            let sh = CGPoint(x: cx + CGFloat(side) * h * 0.09, y: torsoTop.y + h * 0.02)
            limb(from: sh, angle: side * (0.18 + 0.1 * k) + s * 0.2, length: h * 0.30 * CGFloat(1 - max(0, s) * 0.3), bend: -side * (0.3 + 0.9 * k), width: h * 0.035, color: blue)
        }
        // Head bobs slightly less than the torso (stabilised gaze).
        let headR = h * 0.06
        let head = CGRect(x: cx - headR, y: torsoTop.y - headR * 2.1 + bob * 0.3, width: headR * 2, height: headR * 2)
        g.fill(Path(ellipseIn: head), with: .color(Color(red: 1.0, green: 0.87, blue: 0.78)))
        // Ponytail lags behind the head: follow-through.
        let tail = CGPoint(x: cx + CGFloat(sin(phase - 0.9)) * h * (0.02 + 0.06 * k), y: head.minY - headR * 0.2 + CGFloat(cos(phase - 0.9)) * h * 0.02 * CGFloat(k))
        var hair = Path(); hair.move(to: CGPoint(x: cx, y: head.minY + headR * 0.2)); hair.addQuadCurve(to: CGPoint(x: tail.x, y: head.maxY + headR * 1.6), control: CGPoint(x: tail.x + headR, y: tail.y))
        g.stroke(hair, with: .color(Color(red: 0.08, green: 0.12, blue: 0.35)), style: StrokeStyle(lineWidth: headR * 0.8, lineCap: .round))
    }
}

/// Reference type so per-frame integration never triggers a SwiftUI state update.
final class RunnerClock {
    var phase: Double = 0
    var smoothed: Double = 0
    var last: Date?
    var runFrame: Double = 0
    var stopStart: Date?
    var wasRunning = false
    var lastContact = -1
    var lastFrameTime: Date?
}

/// v1.27: frames are 520×720 (native video resolution). The run loop is motion-interpolated to
/// 72 fps (93 frames, 3× the source) and the slow-down clip plays at its full 24 fps (240 frames).
/// Frames stay WebP-compressed in memory and are decoded on demand, so memory stays small.
final class CharacterAtlas {
    static let shared: CharacterAtlas? = CharacterAtlas()
    private let runBlob: Data, stopBlob: Data
    private let run: [[Int]], stop: [[Int]]
    private let runFPS: Double, stopFPS: Double
    let contacts: [Int]
    private var cache: [Int: UIImage] = [:]
    private var cacheOrder: [Int] = []
    private init?() {
        guard let dir = Bundle.main.url(forResource: "character", withExtension: nil),
              let data = try? Data(contentsOf: dir.appendingPathComponent("char_manifest.json")),
              let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let r = m["run"] as? [String: Any], let st = m["stop"] as? [String: Any],
              let rb = try? Data(contentsOf: dir.appendingPathComponent(r["blob"] as? String ?? "")),
              let sb = try? Data(contentsOf: dir.appendingPathComponent(st["blob"] as? String ?? "")) else { return nil }
        runBlob = rb; stopBlob = sb
        func valid(_ list: Any?, _ blob: Data) -> [[Int]] {
            ((list as? [[Int]]) ?? []).filter { $0.count == 2 && $0[0] >= 0 && $0[1] > 0 && $0[0] + $0[1] <= blob.count }
        }
        run = valid(r["frames"], rb); stop = valid(st["frames"], sb)
        runFPS = r["fps"] as? Double ?? 72; stopFPS = st["fps"] as? Double ?? 24
        contacts = r["contacts"] as? [Int] ?? []
        guard !run.isEmpty, !stop.isEmpty else { return nil }
    }
    private func image(_ list: [[Int]], _ blob: Data, _ index: Int, key: Int) -> UIImage? {
        if let hit = cache[key] { return hit }
        let e = list[max(0, min(list.count - 1, index))]
        guard let img = UIImage(data: blob.subdata(in: e[0] ..< e[0] + e[1])) else { return nil }
        cache[key] = img; cacheOrder.append(key)
        if cacheOrder.count > 24 { cache[cacheOrder.removeFirst()] = nil }
        return img
    }
    /// Standing pose used as the chat avatar.
    var portrait: UIImage? { image(stop, stopBlob, stop.count - 1, key: 100_000 + stop.count - 1) }
    /// Run loop plays faster with speed; when the car stops the slow-down clip plays once and holds.
    func frame(for c: RunnerClock, speed: Double, now: Date) -> UIImage? {
        if speed >= 3 {
            c.wasRunning = true; c.stopStart = nil
            let rate = min(1.7, max(0.55, speed / 45))
            let dt = c.lastFrameTime.map { min(0.1, max(0, now.timeIntervalSince($0))) } ?? 0
            c.lastFrameTime = now
            c.runFrame = (c.runFrame + runFPS * rate * dt).truncatingRemainder(dividingBy: Double(run.count))
            let i = max(0, min(run.count - 1, Int(c.runFrame)))
            let near = contacts.contains { abs($0 - i) <= 1 }
            if near, c.lastContact < 0 { c.lastContact = i; CharacterFootstep.play() } else if !near { c.lastContact = -1 }
            return image(run, runBlob, i, key: i)
        }
        c.lastFrameTime = now
        if c.wasRunning, c.stopStart == nil { c.stopStart = now }
        guard let start = c.stopStart else { return portrait }
        let i = max(0, min(stop.count - 1, Int(max(0, now.timeIntervalSince(start)) * stopFPS)))
        return image(stop, stopBlob, i, key: 100_000 + i)
    }
}

/// Soft footstep synced to the frames where a foot lands.
enum CharacterFootstep {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "running.footsteps") as? Bool ?? true }
    private static let generator = UIImpactFeedbackGenerator(style: .soft)
    static func play() {
        guard enabled else { return }
        generator.impactOccurred(intensity: 0.35)
    }
}
