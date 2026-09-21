import AVFoundation

/// v30 streaming output for synthesized speech: sentences are scheduled on one player node as soon as
/// they are ready, so long announcements start quickly and never restart a player between sentences.
final class VoicePlaybackEngine {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var generation = 0
    private var pending = 0
    private var inputFinished = false
    private var onDrained: (() -> Void)?
    private var configObserver: NSObjectProtocol?
    var volume: Float { get { node.volume } set { node.volume = max(0, min(1, newValue)) } }

    init() {
        engine.attach(node)
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            // Route changes (CarPlay/Bluetooth) stop the engine; restart on the next sentence.
            guard let self else { return }
            if self.pending > 0 { self.finish() }
        }
    }
    deinit { if let configObserver { NotificationCenter.default.removeObserver(configObserver) } }

    /// Starts a new utterance; any previous one is dropped.
    func begin(sampleRate: Int, onDrained: @escaping () -> Void) throws {
        stop()
        generation += 1
        self.onDrained = onDrained
        inputFinished = false; pending = 0
        let wanted = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)
        if format != wanted || !engine.isRunning {
            engine.stop()
            engine.disconnectNodeOutput(node)
            engine.connect(node, to: engine.mainMixerNode, format: wanted)
            format = wanted
            engine.prepare()
            try engine.start()
        }
        node.play()
    }

    func schedule(_ samples: [Float], gap: Double) {
        guard let format, !samples.isEmpty else { return }
        // 60ms leading silence: un-mutes DAC / Bluetooth amp cleanly without perceptible lag
        let lead = Int(format.sampleRate * 0.06)
        // 80-100ms trailing silence: ensures final syllables exit hardware buffer cleanly
        let trail = Int(format.sampleRate * min(max(0.08, gap), 0.25))
        let total = lead + samples.count + trail
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)) else { return }
        buffer.frameLength = AVAudioFrameCount(total)
        let channel = buffer.floatChannelData![0]
        channel.update(repeating: 0, count: total)
        samples.withUnsafeBufferPointer { (channel + lead).update(from: $0.baseAddress!, count: samples.count) }
        pending += 1
        let token = generation
        node.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.pending -= 1
                if self.pending == 0, self.inputFinished { self.finish() }
            }
        }
    }

    /// No more sentences will be scheduled for this utterance.
    func endInput() {
        inputFinished = true
        if pending == 0 { finish() }
    }

    func stop() {
        generation += 1
        onDrained = nil; pending = 0; inputFinished = false
        if engine.isRunning { node.stop() }
    }

    private func finish() {
        let done = onDrained
        onDrained = nil; pending = 0; inputFinished = false
        generation += 1
        // Do not call node.stop() here; let the node naturally finish playing all buffered frames to the hardware/Bluetooth output.
        done?()
    }
}

/// Hardware-accelerated playlist player for pre-recorded studio clips.
/// Seamlessly compiles multi-part clips into a single continuous PCM buffer with 22ms crossfading,
/// completely eliminating Bluetooth drops, pops, and audio stuttering.
final class RecordedAudioPlaylistPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var steps: [(url: URL, gap: Double)] = []
    private var currentIndex = 0
    private var completion: (() -> Void)?
    private var workItem: DispatchWorkItem?
    private var currentVolume: Float = 1.0

    func play(steps: [(url: URL, gap: Double)], volume: Float, completion: @escaping () -> Void) {
        stop()
        guard !steps.isEmpty else { completion(); return }
        self.completion = completion
        self.currentVolume = volume

        // 1. Fast path: Render all clips into one continuous PCM buffer with crossfading and play in ONE pass.
        // This ensures zero Bluetooth latency between words and prevents audio buffer underruns.
        if let rendered = RecordedVoice.render(steps) {
            let wav = Self.wavData(from: rendered.samples, sampleRate: rendered.sampleRate)
            do {
                let p = try AVAudioPlayer(data: wav)
                p.delegate = self
                p.volume = volume
                p.prepareToPlay()
                p.play()
                self.player = p
                return
            } catch {
                // If in-memory WAV playback fails, fall through to sequential playback
            }
        }

        // 2. Fallback: Sequential playback if rendering was unavailable
        self.steps = steps
        self.currentIndex = 0
        playCurrent()
    }

    private func playCurrent() {
        guard currentIndex < steps.count else {
            finish()
            return
        }
        let step = steps[currentIndex]
        do {
            let p = try AVAudioPlayer(contentsOf: step.url)
            p.delegate = self
            p.volume = currentVolume
            p.prepareToPlay()
            p.play()
            self.player = p
        } catch {
            currentIndex += 1
            playCurrent()
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if steps.isEmpty {
            // Single continuous WAV buffer playback finished
            finish()
            return
        }
        guard currentIndex < steps.count else { finish(); return }
        let currentStep = steps[currentIndex]
        currentIndex += 1
        if currentIndex < steps.count {
            let gap = currentStep.gap
            if gap > 0 {
                let work = DispatchWorkItem { [weak self] in
                    self?.playCurrent()
                }
                self.workItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + gap, execute: work)
            } else {
                playCurrent()
            }
        } else {
            finish()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if steps.isEmpty {
            finish()
            return
        }
        currentIndex += 1
        playCurrent()
    }

    private func finish() {
        let done = completion
        stop()
        done?()
    }

    func stop() {
        workItem?.cancel()
        workItem = nil
        player?.stop()
        player = nil
        steps = []
        currentIndex = 0
        completion = nil
    }

    /// Converts raw mono 32-bit float samples into standard 16-bit PCM WAV Data for instant, zero-latency AVAudioPlayer playback.
    private static func wavData(from samples: [Float], sampleRate: Int) -> Data {
        var data = Data()
        let numSamples = samples.count
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = UInt32(sampleRate * Int(numChannels) * Int(bitsPerSample / 8))
        let blockAlign: UInt16 = numChannels * (bitsPerSample / 8)
        let subchunk2Size: UInt32 = UInt32(numSamples * Int(numChannels) * Int(bitsPerSample / 8))
        let chunkSize: UInt32 = 36 + subchunk2Size

        data.append(contentsOf: [UInt8]("RIFF".utf8))
        var cSize = chunkSize.littleEndian
        data.append(Data(bytes: &cSize, count: 4))
        data.append(contentsOf: [UInt8]("WAVE".utf8))

        data.append(contentsOf: [UInt8]("fmt ".utf8))
        var subchunk1Size: UInt32 = UInt32(16).littleEndian
        data.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat: UInt16 = UInt16(1).littleEndian
        data.append(Data(bytes: &audioFormat, count: 2))
        var channels = numChannels.littleEndian
        data.append(Data(bytes: &channels, count: 2))
        var sRate = UInt32(sampleRate).littleEndian
        data.append(Data(bytes: &sRate, count: 4))
        var bRate = byteRate.littleEndian
        data.append(Data(bytes: &bRate, count: 4))
        var bAlign = blockAlign.littleEndian
        data.append(Data(bytes: &bAlign, count: 2))
        var bps = bitsPerSample.littleEndian
        data.append(Data(bytes: &bps, count: 2))

        data.append(contentsOf: [UInt8]("data".utf8))
        var s2Size = subchunk2Size.littleEndian
        data.append(Data(bytes: &s2Size, count: 4))

        data.reserveCapacity(data.count + numSamples * 2)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            var intSample = Int16(clamped * 32767.0).littleEndian
            data.append(Data(bytes: &intSample, count: 2))
        }
        return data
    }
}
