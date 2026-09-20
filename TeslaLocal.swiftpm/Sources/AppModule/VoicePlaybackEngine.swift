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

/// Hardware-accelerated playlist player for pre-recorded studio MP3 clips.
/// Avoids AVAudioEngine buffer underrun, sample-rate conversion distortion, and clipping.
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
        self.steps = steps
        self.currentIndex = 0
        self.completion = completion
        self.currentVolume = volume
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
}
