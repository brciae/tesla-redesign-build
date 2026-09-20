import AVFoundation
import AudioToolbox

/// v30 on-device voice shaping, rendered offline per sentence:
/// time-pitch → 10-band EQ → radio (distortion) → punch (dynamics) → room (reverb).
enum VoiceEffects {
    static func apply(_ raw: [Float], sampleRate: Int, profile: VoiceProfile) throws -> [Float] {
        guard !raw.isEmpty, profile.hasEffects else { return raw }
        // v35: character shaping (formant warp + breath) runs first, in our own DSP, because the pitch
        // unit below moves formants together with pitch and cannot produce an anime timbre on its own.
        let samples = CharacterVoiceDSP.apply(raw, sampleRate: sampleRate, formant: profile.formant, breath: profile.breath,
                                              breathWarmth: profile.breathWarmth, life: profile.life,
                                              vibrato: profile.wobble, thickness: profile.thick, warmth: profile.drive)
        guard profile.needsEngineChain else { return normalised(samples) }
        // Stereo throughout: Apple's reverb (and some other units) reject mono connections (-10868).
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 2),
              let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw NSError(domain: "VoiceEffects", code: 1)
        }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        var chain: [AVAudioNode] = [player]
        if profile.pitch != 0 {
            let shift = AVAudioUnitTimePitch()
            shift.pitch = max(-800, min(800, profile.pitch)); shift.rate = 1; shift.overlap = 12
            chain.append(shift)
        }
        if profile.eq.contains(where: { $0 != 0 }) {
            let eq = AVAudioUnitEQ(numberOfBands: VoiceProfile.bands.count)
            for (i, band) in eq.bands.enumerated() {
                band.frequency = min(VoiceProfile.bands[i], Float(sampleRate) * 0.45)
                band.filterType = i == 0 ? .lowShelf : i == VoiceProfile.bands.count - 1 ? .highShelf : .parametric
                if band.filterType == .parametric { band.bandwidth = 1.0 }
                band.gain = i < profile.eq.count ? max(-12, min(12, profile.eq[i])) : 0
                band.bypass = band.gain == 0
            }
            // Headroom for boosts; the final normaliser restores level.
            eq.globalGain = -max(0, profile.eq.max() ?? 0) * 0.6
            chain.append(eq)
        }
        if profile.radio > 0 {
            let radio = AVAudioUnitDistortion()
            radio.loadFactoryPreset(.speechRadioTower)
            radio.preGain = -6
            radio.wetDryMix = max(0, min(70, profile.radio))
            chain.append(radio)
        }
        if profile.punch > 0 {
            let desc = AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_DynamicsProcessor,
                                                 componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
            let dynamics = AVAudioUnitEffect(audioComponentDescription: desc)
            let unit = dynamics.audioUnit
            let amount = max(0, min(1, profile.punch))
            // Parameter ids: 0 threshold (dB), 1 headroom (dB), 4 attack (s), 5 release (s), 6 overall gain (dB).
            AudioUnitSetParameter(unit, 0, kAudioUnitScope_Global, 0, -12 - 18 * amount, 0)
            AudioUnitSetParameter(unit, 1, kAudioUnitScope_Global, 0, 6 - 4 * amount, 0)
            AudioUnitSetParameter(unit, 4, kAudioUnitScope_Global, 0, 0.002, 0)
            AudioUnitSetParameter(unit, 5, kAudioUnitScope_Global, 0, 0.12, 0)
            AudioUnitSetParameter(unit, 6, kAudioUnitScope_Global, 0, 4 + 6 * amount, 0)
            chain.append(dynamics)
        }
        if profile.reverb > 0 {
            let room = AVAudioUnitReverb()
            room.loadFactoryPreset(profile.reverb > 25 ? .mediumHall : .mediumRoom)
            room.wetDryMix = max(0, min(60, profile.reverb))
            chain.append(room)
        }
        chain.forEach { engine.attach($0) }
        for (a, b) in zip(chain, chain.dropFirst()) { engine.connect(a, to: b, format: format) }
        engine.connect(chain.last!, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        defer { player.stop(); engine.stop() }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            input.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
            input.floatChannelData![1].update(from: source.baseAddress!, count: samples.count)
        }
        player.scheduleBuffer(input, completionHandler: nil)
        player.play()
        guard let output = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw NSError(domain: "VoiceEffects", code: 2)
        }
        // Time-pitch latency + reverb tail.
        let tail = sampleRate / 4 + (profile.reverb > 0 ? Int(Double(sampleRate) * 0.9) : 0)
        let total = samples.count + tail
        var result = [Float](); result.reserveCapacity(total)
        while result.count < total {
            let frames = AVAudioFrameCount(min(Int(output.frameCapacity), total - result.count))
            let status = try engine.renderOffline(frames, to: output)
            guard status == .success, output.frameLength > 0, let channels = output.floatChannelData else { break }
            let count = Int(output.frameLength)
            if output.format.channelCount >= 2 {
                let left = channels[0], right = channels[1]
                for i in 0..<count { result.append((left[i] + right[i]) * 0.5) }
            } else {
                result.append(contentsOf: UnsafeBufferPointer(start: channels[0], count: count))
            }
        }
        guard !result.isEmpty, result.allSatisfy({ $0.isFinite }) else {
            // The engine chain failed but the character stage may still have produced usable audio.
            return profile.hasCharacter ? normalised(samples) : raw
        }
        // Trim trailing silence, then normalise to a consistent loudness (peak 0.9).
        var end = result.count
        while end > samples.count / 2, abs(result[end - 1]) < 0.0008 { end -= 1 }
        result.removeSubrange(end..<result.count)
        let peak = result.reduce(0) { max($0, abs($1)) }
        if peak > 0.0001 { let gain = min(4, 0.9 / peak); for i in result.indices { result[i] *= gain } }
        return result
    }

    /// Peak-normalise to the same loudness the engine path targets.
    private static func normalised(_ samples: [Float]) -> [Float] {
        var out = samples.map { $0.isFinite ? $0 : 0 }
        let peak = out.reduce(0) { max($0, abs($1)) }
        if peak > 0.0001 { let gain = min(4, 0.9 / peak); for i in out.indices { out[i] *= gain } }
        return out
    }
}

/// Sentence-level splitting so synthesis never cuts a word and the first sentence plays quickly.
enum SpeechChunker {
    static func split(_ text: String, maxLength: Int = 80) -> [String] {
        let clean = text.replacingOccurrences(of: "\n", with: ". ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        var sentences: [String] = []
        var current = ""
        for ch in clean {
            current.append(ch)
            if ".!?。…".contains(ch) {
                let s = current.trimmingCharacters(in: .whitespaces)
                if !s.isEmpty { sentences.append(s) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { sentences.append(rest) }
        var chunks: [String] = []
        for sentence in sentences {
            if sentence.count <= maxLength { chunks.append(sentence); continue }
            // Long sentence: break at a comma, else at the last space before the limit.
            var remaining = Substring(sentence)
            while remaining.count > maxLength {
                let window = remaining.prefix(maxLength)
                let cut = window.lastIndex(of: ",") ?? window.lastIndex(of: " ") ?? window.endIndex
                let piece = remaining[..<cut].trimmingCharacters(in: .whitespaces)
                if !piece.isEmpty { chunks.append(piece) }
                remaining = remaining[cut...].drop(while: { $0 == "," || $0 == " " })
            }
            let tail = remaining.trimmingCharacters(in: .whitespaces)
            if !tail.isEmpty { chunks.append(tail) }
        }
        return chunks
    }
}
