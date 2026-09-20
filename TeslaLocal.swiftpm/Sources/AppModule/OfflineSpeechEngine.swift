import Foundation
import OnnxRuntimeBindings

/// One serial CPU inference worker. v30: sentence streaming, voice-profile styles, effect chain and a
/// small cache so repeated guidance plays instantly. Cancellation is observed between model calls.
final class OfflineSpeechEngine {
    struct Chunk { let samples: [Float]; let sampleRate: Int; let gap: Double }
    private let worker = DispatchQueue(label: "local.ylcompanion.offlinevoice", qos: .userInitiated)
    private let lock = NSLock()
    private var ticket = UUID()
    private var env: ORTEnv?
    private var engine: TextToSpeech?
    private var verified = false
    private var styleCache: (key: String, style: Style)?
    private var audioCache: [String: [Float]] = [:]
    private var cacheOrder: [String] = []

    func cancel() { lock.lock(); ticket = UUID(); lock.unlock() }
    private func matches(_ id: UUID) -> Bool { lock.lock(); defer { lock.unlock() }; return id == ticket }
    func release() { cancel(); worker.async { self.engine = nil; self.env = nil; self.styleCache = nil; self.audioCache = [:]; self.cacheOrder = [] } }

    /// `onChunk` and `completion` run on the main queue and only for the current request.
    func synthesize(text: String, profile: VoiceProfile, rate: Float,
                    onChunk: @escaping (Chunk) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        lock.lock(); let id = UUID(); ticket = id; lock.unlock()
        let profile = profile.validated()
        worker.async {
            let result: Result<Void, Error> = Result {
                guard self.matches(id) else { throw CancellationError() }
                let folder = OfflineVoicePack.directory
                if !self.verified {
                    for file in VoicePackManifest.files { guard self.matches(id) else { throw CancellationError() }; try VoiceFileIntegrity.verify(folder.appendingPathComponent(file.path), file: file) }
                    self.verified = true
                }
                if self.engine == nil {
                    let env = try ORTEnv(loggingLevel: .warning); self.env = env
                    self.engine = try loadTextToSpeech(folder.appendingPathComponent("onnx").path, false, env)
                }
                let engine = self.engine!
                engine.checkCancelled = { [weak self] in guard self?.matches(id) == true else { throw CancellationError() } }
                let styleKey = [profile.base, profile.partner, "\(profile.blend)", "\(profile.rhythm)"].joined(separator: "|")
                let style: Style
                if let cached = self.styleCache, cached.key == styleKey { style = cached.style }
                else { style = try loadProfileStyle(profile, folder: folder); self.styleCache = (styleKey, style) }
                let speed = min(1.5, max(0.7, rate * profile.speed))
                let sentences = SpeechChunker.split(String(text.prefix(1500)))
                guard !sentences.isEmpty else { throw NSError(domain: "VoicePack", code: 5) }
                var produced = false
                for (index, sentence) in sentences.enumerated() {
                    try engine.checkCancelled()
                    let key = "\(profile.hashValue)|\(speed)|\(sentence)"
                    var samples = self.audioCache[key] ?? []
                    if samples.isEmpty {
                        let output = try engine.call(sentence, "ko", style, 8, speed: speed, silenceDuration: 0)
                        guard output.wav.allSatisfy({ $0.isFinite }), output.wav.count <= engine.sampleRate * 40 else { throw NSError(domain: "VoicePack", code: 4) }
                        try engine.checkCancelled()
                        samples = try VoiceEffects.apply(output.wav, sampleRate: engine.sampleRate, profile: profile)
                        if samples.count < engine.sampleRate * 12 { self.remember(key, samples) }
                    }
                    guard samples.contains(where: { abs($0) > 0.0001 }) else { continue }
                    produced = true
                    let chunk = Chunk(samples: samples, sampleRate: engine.sampleRate, gap: index == sentences.count - 1 ? 0.05 : profile.pause)
                    DispatchQueue.main.async { if self.matches(id) { onChunk(chunk) } }
                }
                guard produced else { throw NSError(domain: "VoicePack", code: 5) }
            }
            DispatchQueue.main.async { guard self.matches(id) else { return }; completion(result) }
        }
    }

    private func remember(_ key: String, _ samples: [Float]) {
        audioCache[key] = samples
        cacheOrder.removeAll { $0 == key }; cacheOrder.append(key)
        while cacheOrder.count > 40 { audioCache.removeValue(forKey: cacheOrder.removeFirst()) }
    }
}
