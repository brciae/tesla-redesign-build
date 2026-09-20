import Foundation
import AVFoundation

/// v30 voice model: a base Supertonic speaker (5 female, 5 male), an optional blend partner of the same
/// gender, delivery (speed/pause/pitch) and on-device sound shaping (10-band EQ, room, radio, punch).
struct VoiceProfile: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var name: String
    var female: Bool
    var base: String
    var partner: String
    var blend: Float = 1          // timbre weight of `base` (1 = pure base)
    var rhythm: Float = 1         // rhythm/duration weight of `base`
    var speed: Float = 1          // 0.75 ... 1.3
    var pause: Double = 0.16      // seconds between sentences
    var pitch: Float = 0          // cents, −800 ... 800
    var eq: [Float] = Array(repeating: 0, count: 10)   // dB per band, −12 ... 12
    var reverb: Float = 0         // wet %, 0 ... 60
    var radio: Float = 0          // wet %, 0 ... 70
    var punch: Float = 0          // compression amount, 0 ... 1
    // v35 character shaping. Optional so profiles saved by older versions still decode.
    var formantShift: Float?      // vocal-tract stretch for the 1.5-3 kHz region, 1 ... 1.4
    var breathiness: Float?       // aspiration noise mixed with the voice, 0 ... 0.4
    var breathBody: Float?        // 0 = airy hiss, 1 = close breathy body (sultry), 0 ... 1
    var liveliness: Float?        // pitch-contour expansion: flat TTS intonation is the "machine" sound, 0 ... 1
    var vibrato: Float?           // cents of slow modulation so held vowels are never perfectly steady, 0 ... 60
    var thickness: Float?         // detuned chorus copies for a thick, lush voice, 0 ... 0.5
    var warmth: Float?            // gentle saturation, adds low-order harmonics, 0 ... 0.6
    var toneID: String?           // CharacterTone raw value: rewrites sentence endings before synthesis

    /// Formant stretch actually applied (1 = untouched).
    var formant: Float { min(1.4, max(1, formantShift ?? 1)) }
    /// Breath noise actually applied (0 = none).
    var breath: Float { min(0.4, max(0, breathiness ?? 0)) }
    var breathWarmth: Float { min(1, max(0, breathBody ?? 0)) }
    var life: Float { min(1, max(0, liveliness ?? 0)) }
    var wobble: Float { min(60, max(0, vibrato ?? 0)) }
    var thick: Float { min(0.5, max(0, thickness ?? 0)) }
    var drive: Float { min(0.6, max(0, warmth ?? 0)) }
    /// True when the character stage has anything to do.
    var hasCharacter: Bool { formant > 1.001 || breath > 0.001 || life > 0.001 || wobble > 0.5 || thick > 0.005 || drive > 0.005 }
    /// True when the AVAudioEngine chain has something to do; character shaping runs before it.
    var needsEngineChain: Bool { pitch != 0 || reverb > 0 || radio > 0 || punch > 0 || eq.contains { $0 != 0 } }

    static let bands: [Float] = [60, 125, 250, 500, 1000, 2000, 4000, 8000, 12000, 16000]
    static let bandLabels = ["60", "125", "250", "500", "1k", "2k", "4k", "8k", "12k", "16k"]

    var hasEffects: Bool { needsEngineChain || hasCharacter }

    func validated() -> VoiceProfile {
        var v = self
        let pool = female ? VoiceLibrary.femaleBases : VoiceLibrary.maleBases
        if !pool.contains(v.base) { v.base = pool[0] }
        if !pool.contains(v.partner) { v.partner = v.base }
        func clamp(_ x: Float, _ lo: Float, _ hi: Float, _ fallback: Float) -> Float { x.isFinite ? min(hi, max(lo, x)) : fallback }
        v.blend = clamp(v.blend, 0, 1, 1); v.rhythm = clamp(v.rhythm, 0, 1, 1)
        v.speed = clamp(v.speed, 0.75, 1.3, 1)
        v.pause = v.pause.isFinite ? min(0.6, max(0, v.pause)) : 0.16
        v.pitch = clamp(v.pitch, -800, 800, 0)
        v.eq = (0..<10).map { i in i < v.eq.count ? clamp(v.eq[i], -12, 12, 0) : 0 }
        v.reverb = clamp(v.reverb, 0, 60, 0); v.radio = clamp(v.radio, 0, 70, 0); v.punch = clamp(v.punch, 0, 1, 0)
        if let f = v.formantShift { v.formantShift = f.isFinite ? min(1.4, max(1, f)) : nil }
        if let b = v.breathiness { v.breathiness = b.isFinite ? min(0.4, max(0, b)) : nil }
        if let b = v.breathBody { v.breathBody = b.isFinite ? min(1, max(0, b)) : nil }
        if let l = v.liveliness { v.liveliness = l.isFinite ? min(1, max(0, l)) : nil }
        if let w = v.vibrato { v.vibrato = w.isFinite ? min(60, max(0, w)) : nil }
        if let t = v.thickness { v.thickness = t.isFinite ? min(0.5, max(0, t)) : nil }
        if let w = v.warmth { v.warmth = w.isFinite ? min(0.6, max(0, w)) : nil }
        if let t = v.toneID, CharacterTone(rawValue: t) == nil { v.toneID = nil }
        v.name = String(v.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
        if v.name.isEmpty { v.name = "나만의 음성" }
        return v
    }
}

/// One row of the voice picker: an iPhone system voice or an on-device engine voice.
struct VoiceChoice: Identifiable, Hashable {
    let id: String          // "" = iPhone default, "offline:…" = engine voice, else AVSpeechSynthesisVoice identifier
    let name: String
    let detail: String
    var female: Bool
    /// Recorded voices ship a character portrait; engine and system voices have none.
    var portrait: URL? = nil
}

enum VoiceLibrary {
    static let femaleBases = ["F1", "F2", "F3", "F4", "F5"]
    static let maleBases = ["M1", "M2", "M3", "M4", "M5"]
    static let baseTraits = ["F1": "맑고 또렷함", "F2": "부드러움", "F3": "낮고 차분함", "F4": "단정한 아나운서", "F5": "밝고 경쾌함",
                             "M1": "편안한 중저음", "M2": "젊고 활기참", "M3": "굵고 묵직함", "M4": "또렷한 지휘", "M5": "가볍고 친근함"]

    static func base(_ id: String) -> VoiceProfile {
        VoiceProfile(id: "base:" + id, name: (VoicePackManifest.names[id] ?? id), female: id.hasPrefix("F"), base: id, partner: id)
    }

    /// v34: the picker keeps two clean engine voices plus three character voices (bright / soft / sultry),
    /// v41 lineup. The three the owner picked from the v40 audition (A, C, E) are now the everyday
    /// voices, plus two built toward two *different* characters rather than their common ground:
    /// one warm, low and close, one bright, light and quick. These are voices of our own built from the
    /// bundled speakers — not an imitation of any real person, and not offered as one.
    static let presets: [VoiceProfile] = [
        // A — clear and even. The default.
        VoiceProfile(id: "preset:clear-f", name: "지연 (맑고 또렷)", female: true, base: "F1", partner: "F1", blend: 1, rhythm: 1, speed: 0.98, pause: 0.18,
                     eq: [0, 1.5, 1.5, 0.5, 0, 1.5, 2, 1, -1, -2], reverb: 3, punch: 0.22, toneID: "thirties"),
        // C — F1 carried into F4's evenness: the anchor read.
        VoiceProfile(id: "preset:guide-f", name: "하린 (차분한 안내)", female: true, base: "F1", partner: "F4", blend: 0.55, rhythm: 0.55, speed: 0.97, pause: 0.18,
                     eq: [0, 1.5, 1.5, 0.5, 0, 1.5, 2, 1, -1, -2], reverb: 3, punch: 0.22, toneID: "thirties"),
        // E — lower and closer, as if speaking from the passenger seat rather than a PA.
        VoiceProfile(id: "preset:close-f", name: "유나 (낮고 가까운)", female: true, base: "F1", partner: "F1", blend: 1, rhythm: 1, speed: 1.0, pause: 0.18, pitch: -40,
                     eq: [0, 1.5, 1.5, 0.5, 0, 1.5, 2, 1, -1, -2], reverb: 3, punch: 0.22,
                     breathiness: 0.06, breathBody: 0.5, thickness: 0.08, warmth: 0.2, toneID: "twenties"),
        // Character 1 — warm and unhurried: the darkest bundled speaker (F3, spectral centroid 1.1 kHz),
        // body lifted at 125–250 Hz, air pulled down, a close breath rather than an airy one, slow.
        VoiceProfile(id: "preset:warm-f", name: "다인 (따뜻하고 낮은)", female: true, base: "F3", partner: "F3", blend: 1, rhythm: 1, speed: 0.93, pause: 0.24, pitch: -20,
                     eq: [1, 3, 2.5, 1, 0, 0.5, 1.5, 0, -2, -3], reverb: 5, punch: 0.2,
                     breathiness: 0.10, breathBody: 0.85, liveliness: 0.2, vibrato: 6, thickness: 0.10, warmth: 0.25, toneID: "twenties"),
        // Character 2 — bright and light: the clearest speaker lifted a little, a slightly shorter tract,
        // presence up, low end trimmed so nothing weighs it down, quicker on its feet.
        VoiceProfile(id: "preset:bright-f", name: "세아 (맑고 가벼운)", female: true, base: "F1", partner: "F1", blend: 1, rhythm: 1, speed: 1.03, pause: 0.12, pitch: 70,
                     eq: [-3, -2, -0.5, 0, 0.5, 2, 2.5, 2, 1.5, 0], reverb: 2, punch: 0.28,
                     formantShift: 1.06, breathiness: 0.05, breathBody: 0.2, liveliness: 0.3, vibrato: 5, thickness: 0.03, warmth: 0.12, toneID: "twenties"),
        // The one male voice stays for anyone who wants it.
        VoiceProfile(id: "preset:clear-m", name: "도현 (남성)", female: false, base: "M1", partner: "M4", blend: 0.85, rhythm: 0.9, speed: 0.98, pause: 0.16,
                     eq: [1, 1, 0, 0, 1, 1, 1, 0, -1, -2], toneID: "thirties")
    ]

    static let eqPresets: [(name: String, gains: [Float])] = [
        ("평탄", Array(repeating: 0, count: 10)),
        ("따뜻하게", [4, 3, 2, 1, 0, -1, -1, -2, -2, -3]),
        ("밝고 또렷하게", [-2, -1, 0, 0, 1, 3, 4, 3, 2, 1]),
        ("저음 강조", [7, 6, 4, 1, 0, 0, 0, 0, 0, 0]),
        ("라디오", [-12, -10, -4, 1, 4, 5, 3, -4, -12, -12]),
        ("전화기", [-12, -12, -8, 0, 5, 6, 2, -10, -12, -12]),
        ("차 안 소음 대응", [-3, -2, 0, 0, 2, 4, 5, 3, 1, 0])
    ]

    private static let customKey = "voiceCustomProfiles"
    static var customs: [VoiceProfile] {
        get {
            guard let data = UserDefaults.standard.data(forKey: customKey),
                  let list = try? JSONDecoder().decode([VoiceProfile].self, from: data) else { return [] }
            return list.map { $0.validated() }.filter { $0.id.hasPrefix("custom:") }
        }
        set {
            let clean = Array(newValue.map { $0.validated() }.filter { $0.id.hasPrefix("custom:") }.prefix(12))
            UserDefaults.standard.set(try? JSONEncoder().encode(clean), forKey: customKey)
        }
    }
    static func save(_ profile: VoiceProfile) {
        var list = customs
        if let i = list.firstIndex(where: { $0.id == profile.id }) { list[i] = profile } else { list.append(profile) }
        customs = list
    }
    static func delete(_ id: String) { customs = customs.filter { $0.id != id } }

    /// Resolves an identifier without the "offline:" prefix. Legacy v28/v29 ids map to the nearest new voice.
    static func profile(for id: String) -> VoiceProfile? {
        if id.hasPrefix("base:") { let b = String(id.dropFirst(5)); return (femaleBases + maleBases).contains(b) ? base(b) : nil }
        if (femaleBases + maleBases).contains(id) { return base(id) }
        if let p = presets.first(where: { $0.id == id }) { return p }
        if id.hasPrefix("custom:") { return customs.first { $0.id == id } }
        // v28–v30 character ids (FC1…, preset:night-dj, …) fall back to the clean voice of the same gender.
        // v41 retired the anime presets; anyone still on one lands on the nearest new voice.
        let retired = ["preset:anime-bright": "preset:bright-f", "preset:anime-soft": "preset:clear-f", "preset:anime-sultry": "preset:warm-f"]
        if let replacement = retired[id], let p = presets.first(where: { $0.id == replacement }) { return p }
        let legacyMale = ["preset:anchor-m", "preset:crew", "preset:robot"]
        // By id, not by position: the lineup is reordered between versions and an index silently sent
        // every legacy male selection to whichever voice happened to sit second.
        let defaultMale = presets.first { $0.id == "preset:clear-m" }
        let defaultFemale = presets.first { $0.id == "preset:clear-f" }
        if id.hasPrefix("MC") || legacyMale.contains(id) { return defaultMale }
        if id.hasPrefix("FC") || id.hasPrefix("preset:") { return defaultFemale }
        if id == "CUSTOM" { return customs.first }
        return nil
    }

    static func displayName(_ id: String) -> String {
        guard let p = profile(for: id) else { return id }
        return p.name + (p.female ? " · 여성" : " · 남성")
    }
}

extension VoiceLibrary {
    /// Up to two Korean iPhone voices, best quality first, plus the engine voices.
    /// Nothing else is offered in the picker; extra iPhone voices sit behind "모든 iPhone 음성".
    static func curated() -> [VoiceChoice] {
        // v42: the recorded voice first. It is the only one that sounds like a person, so it leads;
        // engine voices follow, and the iPhone system voices are the fallback rather than the headline.
        recordedChoices()
    }

    /// The bundled recorded guidance voices, offered only when their clips are actually in the build.
    static func recordedChoices() -> [VoiceChoice] {
        RecordedVoice.voices.map { voice in
            let style = voice.style.isEmpty ? "실제 녹음" : "실제 녹음 · " + voice.style
            return VoiceChoice(id: voice.id, name: voice.displayName,
                               detail: "\(style) · 고정 안내 \(voice.count)문장",
                               female: true, portrait: voice.portrait)
        }
    }

    static func engineChoices() -> [VoiceChoice] {
        guard VoicePackManifest.installed else { return [] }
        let order = ["preset:clear-f", "preset:guide-f", "preset:close-f", "preset:warm-f", "preset:bright-f", "preset:clear-m"]
        let sorted = presets.sorted { (order.firstIndex(of: $0.id) ?? 99) < (order.firstIndex(of: $1.id) ?? 99) }
        return sorted.map { profile in
            let detail = profile.tone.map { $0.title } ?? "앱 내장 · 네트워크 없이 동작"
            return VoiceChoice(id: "offline:" + profile.id, name: profile.name, detail: detail, female: profile.female)
        }
    }

    static func systemChoices(limit: Int? = nil) -> [VoiceChoice] {
        let ranked = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("ko") }
            .sorted { rank($0) > rank($1) }
        let chosen = limit.map { Array(ranked.prefix($0)) } ?? ranked
        return chosen.map {
            VoiceChoice(id: $0.identifier, name: $0.name,
                        detail: quality($0) + " · iPhone 음성", female: $0.gender != .male)
        }
    }

    private static func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
        switch voice.quality {
        case .premium: return 3
        case .enhanced: return 2
        default: return 1
        }
    }
    private static func quality(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return "프리미엄"
        case .enhanced: return "고품질"
        default: return "기본"
        }
    }

    /// Name shown for whatever is selected, including iPhone voices and the iPhone default.
    static func label(for identifier: String) -> String {
        if identifier.isEmpty { return "한국어 · iPhone 기본" }
        if let voice = RecordedVoice.resolved(identifier) { return voice.displayName + " · 여성" }
        if identifier.hasPrefix("offline:") { return displayName(String(identifier.dropFirst(8))) }
        if let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.identifier == identifier }) {
            return voice.name + " · " + quality(voice)
        }
        return "iPhone 음성"
    }
}
