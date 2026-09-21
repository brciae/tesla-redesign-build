import Foundation
import AVFoundation

/// v42 recorded guidance voice.
///
/// Every earlier attempt to make the bundled synthesis engine sound like a person failed for the same
/// reason: it is a small on-device model, and no amount of filtering turns it into a human read. So the
/// announcements the app makes most often are no longer synthesised at all — they are pre-recorded, once,
/// and played back. Anything the recordings do not cover still goes to the engine, unchanged.
///
/// Two kinds of clip are bundled:
///   * `phrases` — whole sentences, matched by their text.
///   * `distance` + `action` — the two halves of a turn call ("삼백 미터 앞," + "좌회전입니다."), so the
///     junction distance can vary without recording every combination. The navigation bridge snaps the
///     spoken distance to the recorded set, which is what a car navigation system does anyway.
///
/// The recordings were produced with Typecast (free plan: personal use, credited in 설정 → 정보).
enum RecordedVoice {
    static let prefix = "recorded:"
    static let credit = "음성·캐릭터 이미지 제작: Typecast"
    /// Sentences the recordings do not cover are spoken by this engine voice rather than left silent.
    static let fallbackProfileID = "preset:guide-f"

    /// One bundled recorded voice. Several can ship at once; each is a folder with its own manifest.
    struct Voice: Identifiable {
        var id: String            // "recorded:yumi"
        var name: String          // "유미"
        /// One line on how this voice reads, so the picker is not four identical rows.
        var style: String = ""
        /// The character portrait bundled beside the pack, if it shipped with one.
        var portrait: URL?
        /// Playback gain that puts this voice at the same level as the others. The packs were
        /// recorded at different levels and a 4 dB jump on switching voice is the first thing an
        /// owner notices; applying it at playback keeps the clips themselves untouched.
        var gain: Float = 1
        var bank: Bank
        var displayName: String { name + " (녹음 음성)" }
        var count: Int { bank.phrases.count }
    }

    struct Bank {
        var folder: URL
        var phrases: [String: String] = [:]     // normalised sentence -> file
        var distance: [String: String] = [:]    // normalised distance phrase -> file
        var action: [String: String] = [:]      // normalised action -> file
        // v43 word-level pieces, so a sentence with a number in it can still be one voice:
        // "목적지까지" + "십이" + "분 남았습니다".
        var head: [String: String] = [:]        // opening clause, continuing intonation
        var number: [String: String] = [:]      // 영 … 구십구, 백 … 구백, 한 … 열두
        var tail: [String: String] = [:]        // closing clause, sentence-final intonation
        var phraseCount: Int { phrases.count }
        var composable: Bool { !number.isEmpty && !tail.isEmpty }
    }

    /// Loaded once from the app bundle. Settable so the build-time probe can check the matching rules
    /// against the real packs. An empty list simply means no recorded voice is offered.
    static var voices: [Voice] = load()

    static var available: Bool { !voices.isEmpty }
    static func voice(for identifier: String) -> Voice? { voices.first { $0.id == identifier } }
    /// The voice a selection resolves to: the exact one, else the first bundled voice.
    static func resolved(_ identifier: String) -> Voice? {
        guard identifier.hasPrefix(prefix) else { return nil }
        return voice(for: identifier) ?? voices.first
    }

    private static func load() -> [Voice] {
        // The index names the packs; enumerating a bundle folder is fragile across build layouts.
        let indexes: [URL?] = [
            Bundle.main.url(forResource: "voices", withExtension: "json", subdirectory: "recorded"),
            Bundle.main.url(forResource: "voices", withExtension: "json")
        ]
        guard let index = indexes.compactMap({ $0 }).first,
              let data = try? Data(contentsOf: index),
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        let root = index.deletingLastPathComponent()
        return rows.compactMap { row in
            guard let id = row["id"] as? String, let name = row["name"] as? String else { return nil }
            let folder = (row["folder"] as? String) ?? id
            let dir = root.appendingPathComponent(folder)
            guard let bank = load(manifest: dir.appendingPathComponent("manifest.json")) else { return nil }
            // The portrait is optional: a pack without one still works, it just shows initials.
            var portrait: URL?
            if let file = row["portrait"] as? String {
                let candidate = dir.appendingPathComponent(file)
                if FileManager.default.fileExists(atPath: candidate.path) { portrait = candidate }
                else {
                    let flat = root.appendingPathComponent("\(folder)_\(file)")
                    if FileManager.default.fileExists(atPath: flat.path) { portrait = flat }
                }
            }
            let gain = (row["gain"] as? NSNumber).map { Float(truncating: $0) } ?? 1
            return Voice(id: prefix + id, name: name, style: (row["style"] as? String) ?? "",
                         portrait: portrait, gain: min(max(gain, 0.25), 4), bank: bank)
        }
    }

    /// Reads a pack from an explicit manifest path.
    static func load(manifest url: URL) -> Bank? {
        guard let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var bank = Bank(folder: url.deletingLastPathComponent())
        func fill(_ key: String, _ field: String, into table: inout [String: String]) {
            guard let rows = root[key] as? [[String: Any]] else { return }
            for row in rows {
                guard let file = row["file"] as? String, let text = row[field] as? String else { continue }
                let k = normalise(text)
                if !k.isEmpty { table[k] = file }
            }
        }
        fill("phrases", "text", into: &bank.phrases)
        fill("distance", "label", into: &bank.distance)
        fill("action", "label", into: &bank.action)
        fill("head", "label", into: &bank.head)
        fill("number", "label", into: &bank.number)
        fill("tail", "label", into: &bank.tail)
        return bank.phrases.isEmpty ? nil : bank
    }

    /// Matching ignores spacing and punctuation: "어린이 보호구역입니다." and "어린이 보호 구역입니다"
    /// are the same announcement, and the engine's own spacing should not decide whether the voice is used.
    static func normalise(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { continue }
            if CharacterSet.punctuationCharacters.contains(scalar) { continue }
            if scalar == "·" || scalar == "…" { continue }
            out.append(scalar)
        }
        return String(out)
    }

    private static func sentences(_ text: String) -> [String] {
        text.split(whereSeparator: { ".!?…\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The clip for a "…입니다." tail: either a recorded action word, or a whole recorded sentence.
    /// Safety calls ("급커브 구간입니다.") live in the sentence bank; turn calls live in the action bank.
    private static func tailClip(_ key: String, bank: Bank) -> String? {
        if let file = bank.phrases[key] { return file }
        // Alias fallbacks for phrases
        if key == "오늘도안전운전하세요" || key == "오늘도안전하게운전하세요" {
            if let f = bank.phrases["안전운전하세요"] ?? bank.phrases["오늘도안전하게모실게요"] { return f }
        }
        if key == "차량이현재충전중입니다" || key == "충전이정상적으로진행되고있습니다" {
            if let f = bank.phrases["충전중입니다"] { return f }
        }
        guard key.hasSuffix("입니다") else { return nil }
        return bank.action[String(key.dropLast(3))]
    }

    /// Longest table entry that starts `rest`, with how many characters it used.
    private static func longestMatch(_ rest: Substring, _ table: [String: String]) -> (file: String, length: Int)? {
        guard !rest.isEmpty else { return nil }
        var best: (String, Int)?
        // Longest first, so "삼십" is never read as "삼" + "십". The ceiling is the longest key the
        // table actually holds: a fixed 12 silently lost every opening clause longer than that
        // ("앱에서 관측한 연속 운전 시간이" is 13 characters once the spaces are gone), so those
        // announcements fell through to the engine even though the pack could say them.
        var length = min(rest.count, table.keys.reduce(0) { max($0, $1.count) })
        while length >= 1 {
            let candidate = String(rest.prefix(length))
            if let file = table[candidate] { best = (file, length); break }
            length -= 1
        }
        return best.map { (file: $0.0, length: $0.1) }
    }

    /// A sentence built from recorded words: an optional opening clause, one or more number words,
    /// then a closing clause that must finish the sentence. Anything else is left to the engine —
    /// free-form concatenation would happily produce nonsense that still "matches".
    private static func composed(_ key: String, bank: Bank) -> [String]? {
        guard bank.composable else { return nil }
        var files: [String] = []
        var rest = Substring(key)
        if let head = longestMatch(rest, bank.head) {
            files.append(head.file)
            rest = rest.dropFirst(head.length)
        } else if rest.hasPrefix("주행가능거리는약") {
            if let h = bank.head["남은거리는"] ?? bank.head["약"] {
                files.append(h)
                rest = rest.dropFirst("주행가능거리는약".count)
            }
        } else if rest.hasPrefix("주행가능거리는") {
            if let h = bank.head["남은거리는"] ?? bank.head["약"] {
                files.append(h)
                rest = rest.dropFirst("주행가능거리는".count)
            }
        }
        var matchedNumber = false
        while let num = longestMatch(rest, bank.number) {
            files.append(num.file)
            rest = rest.dropFirst(num.length)
            matchedNumber = true
            if let tail = longestMatch(rest, bank.tail), tail.length == rest.count {
                files.append(tail.file)
                return files
            }
        }
        guard matchedNumber else { return nil }
        if let tail = longestMatch(rest, bank.tail), tail.length == rest.count {
            files.append(tail.file)
            return files
        }
        return nil
    }

    /// Clips for one sentence, or nil when the recordings do not cover it.
    private static func clips(sentence: String, bank: Bank) -> [String]? {
        let key = normalise(sentence)
        guard !key.isEmpty else { return nil }
        if let file = tailClip(key, bank: bank) { return [file] }
        if let words = composed(key, bank: bank) { return words }
        // "<거리>, <나머지>" — the distance is its own recording and the rest is a tail clip, so the
        // junction distance can change without re-recording every announcement it can precede.
        guard let comma = sentence.firstIndex(of: ","), sentence.index(after: comma) < sentence.endIndex else { return nil }
        let head = normalise(String(sentence[sentence.startIndex..<comma]))
        guard let distance = bank.distance[head] else { return nil }
        let tailKey = normalise(String(sentence[sentence.index(after: comma)...]))
        if let tail = tailClip(tailKey, bank: bank) { return [distance, tail] }
        if let words = composed(tailKey, bank: bank) { return [distance] + words }
        return nil
    }

    /// Clips for an announcement with the pause that follows each sentence.
    /// Resilient: skips uncovered sentences if at least one sentence matches.
    static func plan(for text: String, voice identifier: String) -> [(url: URL, gap: Double)]? {
        guard let bank = resolved(identifier)?.bank else { return nil }
        let parts = sentences(text)
        guard !parts.isEmpty else { return nil }
        var plan: [(url: URL, gap: Double)] = []
        for (index, part) in parts.enumerated() {
            guard let found = clips(sentence: part, bank: bank) else { continue }
            let last = index == parts.count - 1
            for (i, file) in found.enumerated() {
                // Clips inside one sentence are crossfaded rather than butted together, so they take
                // no gap at all; only a sentence break gets real silence.
                let gap = i < found.count - 1 ? 0 : (last ? 0 : 0.22)
                plan.append((url: bank.folder.appendingPathComponent(file), gap: gap))
            }
        }
        return plan.isEmpty ? nil : plan
    }

    /// True when `identifier`'s recordings can speak `text` as written.
    static func covers(_ text: String, voice identifier: String) -> Bool { plan(for: text, voice: identifier) != nil }

    /// Renders a plan into one continuous buffer.
    ///
    /// Scheduling the clips back to back left an audible stutter at every join: each clip starts and
    /// ends on a hard edge, and the ear hears the seam. Overlapping them by a few milliseconds with a
    /// linear crossfade removes it, and a sentence break is the only place real silence belongs.
    static func render(_ plan: [(url: URL, gap: Double)], gain: Float = 1) -> (samples: [Float], sampleRate: Int)? {
        var sampleRate = 0
        var out: [Float] = []
        for step in plan {
            guard let clip = samples(step.url), !clip.samples.isEmpty else { return nil }
            if sampleRate == 0 { sampleRate = clip.sampleRate }
            guard clip.sampleRate == sampleRate else { return nil }
            if out.isEmpty {
                out = clip.samples
            } else {
                let overlap = min(Int(0.022 * Double(sampleRate)), out.count / 2, clip.samples.count / 2)
                if overlap > 0 {
                    let start = out.count - overlap
                    for k in 0..<overlap {
                        let t = Float(k) / Float(overlap)
                        out[start + k] = out[start + k] * (1 - t) + clip.samples[k] * t
                    }
                    out.append(contentsOf: clip.samples[overlap...])
                } else {
                    out.append(contentsOf: clip.samples)
                }
            }
            if step.gap > 0 {
                out.append(contentsOf: [Float](repeating: 0, count: Int(step.gap * Double(sampleRate))))
            }
        }
        guard sampleRate > 0, !out.isEmpty else { return nil }
        if gain != 1 {
            // Clip rather than let a loud syllable wrap around; the gains are small and a limiter
            // here would change the voice more than the 0.1% of samples it would catch.
            for i in out.indices { out[i] = min(max(out[i] * gain, -1), 1) }
        }
        return (out, sampleRate)
    }

    /// Decoding the same handful of turn calls over and over is wasteful, so recent clips are kept.
    /// The whole pack is a few megabytes; this cache holds far less than that.
    private static var cache: [String: (samples: [Float], sampleRate: Int)] = [:]
    private static var cacheOrder: [String] = []
    private static let cacheLimit = 48

    /// Decoded mono samples for one clip, resampled to nothing: the pack is already 24 kHz mono.
    static func samples(_ url: URL) -> (samples: [Float], sampleRate: Int)? {
        if let hit = cache[url.path] { return hit }
        guard let decoded = decode(url) else { return nil }
        cache[url.path] = decoded
        cacheOrder.append(url.path)
        while cacheOrder.count > cacheLimit { cache.removeValue(forKey: cacheOrder.removeFirst()) }
        return decoded
    }

    /// Drops the decoded-clip cache; called on a memory warning.
    static func releaseCache() { cache.removeAll(); cacheOrder.removeAll() }

    private static func decode(_ url: URL) -> (samples: [Float], sampleRate: Int)? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        do { try file.read(into: buffer) } catch { return nil }
        guard let channel = buffer.floatChannelData else { return nil }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return nil }
        var mono = [Float](repeating: 0, count: n)
        let channels = Int(format.channelCount)
        if channels == 1 {
            mono.withUnsafeMutableBufferPointer { $0.baseAddress!.update(from: channel[0], count: n) }
        } else {
            for i in 0..<n {
                var sum: Float = 0
                for c in 0..<channels { sum += channel[c][i] }
                mono[i] = sum / Float(channels)
            }
        }
        return (mono, Int(format.sampleRate.rounded()))
    }
}
