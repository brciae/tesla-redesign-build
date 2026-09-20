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
        // 300ms leading silence (7,200 frames @ 24kHz): un-mutes DAC / car Bluetooth amp cleanly before the first syllable
        let lead = Int(format.sampleRate * 0.30)
        // 600ms trailing silence (14,400 frames @ 24kHz): ensures final syllables completely exit the hardware/Bluetooth buffer before completion
        let trail = Int(format.sampleRate * max(0.60, gap))
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
