import SwiftUI
import AVFoundation

/// Single selected-voice output for navigation, safety and vehicle announcements.
/// Exclusively powered by Typecast AI with permanent local audio caching,
/// with instant button-preemption (0ms interruption latency) and zero default-voice clutter.
final class VoiceCoordinator: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var speaking = false
    @Published private(set) var lastText = ""
    @Published private(set) var notice = ""
    @Published private(set) var playbackState = "대기"
    @Published private(set) var outputDescription = ""

    private var typecastPlayer: AVAudioPlayer?
    private var activeTicket: UUID?
    private var releaseWork: DispatchWorkItem?
    private var memoryObserver: NSObjectProtocol?
    private var queue = VoiceQueue()
    private var timer: Timer?
    private var nativeSpeaking = false
    private var nativeActive = false
    private var quietUntil = Date.distantPast
    private var interrupted = false
    private var observer: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var activeManual = false
    private var requestedAt = Date.distantPast
    private var lastGuideText = ""
    private var lastGuideAt = Date.distantPast
    private var navigationSpeaking = false
    private var activePriority = 0

    override init() {
        super.init()
        let defaults = UserDefaults.standard

        // Migrate voice selection to Typecast default (은경)
        let currentVoice = defaults.string(forKey: "voiceIdentifier") ?? ""
        if currentVoice.isEmpty || currentVoice.hasPrefix("recorded:") || currentVoice.hasPrefix("offline:") || (!currentVoice.hasPrefix("typecast:") && !TypecastClient.presetVoices.contains(where: { $0.id == currentVoice })) {
            defaults.set("typecast:은경", forKey: "voiceIdentifier")
        }

        defaults.register(defaults: [
            "voiceAutomations": true, "voiceEnabled": true, "voiceConnection": true, "voiceTrip": true,
            "voiceCharge": true, "voiceBattery": true, "voiceDestination": true, "voiceControl": true,
            "voiceRate": 0.47, "voicePitch": 1.0, "voiceVolume": 0.8, "voiceQuietStart": 22,
            "voiceQuietEnd": 7, "voiceDuck": true, "navVoiceEnabled": true, "navSafetyVoice": true, "navVoiceVolume": 1.0
        ])

        let tick = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.refreshOutput()
            self.drain()
        }
        timer = tick
        RunLoop.main.add(tick, forMode: .common)
        refreshOutput()

        memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cancelCurrent()
        }
        routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshOutput()
        }
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            self.interrupted = raw == AVAudioSession.InterruptionType.began.rawValue
            if self.interrupted {
                self.stop()
                self.notice = "통화·다른 오디오로 안내 일시 중지"
            }
        }
    }

    deinit {
        timer?.invalidate()
        if let memoryObserver { NotificationCenter.default.removeObserver(memoryObserver) }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
    }

    func nativeSession(_ active: Bool) {
        nativeActive = false
        _ = active
        if !active {
            queue.clearNavigation()
            lastGuideText = ""
            lastGuideAt = .distantPast
            nativeSpeaking = false
        }
    }

    func nativeVoice(_ active: Bool) {
        nativeSpeaking = active
        quietUntil = Date().addingTimeInterval(active ? 0 : 1.5)
        if active {
            cancelCurrent()
            playbackState = "내비 안내 우선"
        }
    }

    func navigationGuide(_ text: String, safety: Bool) {
        let d = UserDefaults.standard, now = Date()
        guard !text.isEmpty, d.bool(forKey: "voiceEnabled"), d.bool(forKey: safety ? "navSafetyVoice" : "navVoiceEnabled") else { return }
        let timeSinceLast = now.timeIntervalSince(lastGuideAt)
        if text == lastGuideText && timeSinceLast < 12.0 { return }
        if timeSinceLast < 3.5 && !safety { return }
        if safety && timeSinceLast < 2.5 { return }
        lastGuideText = text
        lastGuideAt = now

        let priority = safety ? 5 : 4
        queue.pruneNavigation(forKey: safety ? "navigation.safety" : "navigation.turn")

        // Safety guidance interrupts regular chatter immediately
        if safety {
            cancelCurrent()
            quietUntil = .distantPast
        }

        queue.add(VoiceItem(key: safety ? "navigation.safety" : "navigation.turn", text: SpeechText.prepare(text), expires: now.addingTimeInterval(8), priority: priority, manual: true), now: now)
        drain()
    }

    func preview(_ text: String) {
        stop()
        if interrupted {
            notice = "통화·다른 오디오가 끝난 뒤 미리 듣기를 다시 눌러 주세요."
            return
        }
        notice = nativeSpeaking ? "내비 안내가 끝나면 미리 듣기 재생" : ""
        playbackState = "안내 대기 중"
        say(text, key: "preview", category: "", priority: 3, ttl: 30, manual: true)
    }

    func announceDashboardStart(destination: String = "") {
        let d = UserDefaults.standard
        guard d.bool(forKey: "voiceEnabled") else { return }
        if !destination.isEmpty {
            say("운전 대시보드를 시작합니다. 목적지 \(destination) 안내를 준비합니다.", key: "dashboard.start", category: "voiceControl", priority: 3, ttl: 8, manual: true)
        } else {
            say("운전 대시보드를 시작합니다. 안전 운전하세요.", key: "dashboard.start", category: "voiceControl", priority: 3, ttl: 8, manual: true)
        }
    }

    /// Speaks an announcement with instant button preemption (cancels previous speech immediately with 0ms delay).
    func say(_ text: String, key: String = "", category: String = "voiceControl", priority: Int = 3, ttl: TimeInterval = 10, manual: Bool = true) {
        let actualKey = key.isEmpty ? "spoken.\(UUID().uuidString)" : key
        let d = UserDefaults.standard
        guard manual || (d.bool(forKey: "voiceEnabled") && d.bool(forKey: category)) else { return }
        let now = Date()
        if !manual && d.bool(forKey: "voiceQuietEnabled") && VoiceQueue.quiet(hour: Calendar.current.component(.hour, from: now), start: d.integer(forKey: "voiceQuietStart"), end: d.integer(forKey: "voiceQuietEnd")) { return }
        let styled = BriefingStyle.selected.phrase(text, category: category)
        let prepared = SpeechText.prepare(styled)

        // INSTANT PREEMPTION: When user taps a button or triggers guidance, immediately cut off previous speech
        // mid-utterance without waiting for it to finish and with zero delay!
        cancelCurrent()
        queue.clear()
        quietUntil = .distantPast

        queue.add(VoiceItem(key: actualKey, text: prepared, expires: now.addingTimeInterval(ttl), priority: priority, manual: manual), now: now)
        drain()
    }

    private func drain() {
        guard !interrupted, !nativeSpeaking, activeTicket == nil, typecastPlayer == nil, Date() >= quietUntil else { return }
        guard let item = queue.next(now: Date()) else { return }
        navigationSpeaking = item.key.hasPrefix("navigation.")
        activePriority = item.priority
        let d = UserDefaults.standard
        if navigationSpeaking && (!d.bool(forKey: "voiceEnabled") || !d.bool(forKey: item.key == "navigation.safety" ? "navSafetyVoice" : "navVoiceEnabled")) {
            navigationSpeaking = false
            activePriority = 0
            drain()
            return
        }
        guard item.manual || d.bool(forKey: "voiceEnabled") else { return }
        if !item.manual && d.bool(forKey: "voiceQuietEnabled") && VoiceQueue.quiet(hour: Calendar.current.component(.hour, from: Date()), start: d.integer(forKey: "voiceQuietStart"), end: d.integer(forKey: "voiceQuietEnd")) { return }

        let tc = TypecastClient.shared
        guard tc.isEnabled && tc.hasKey else {
            notice = "타입캐스트 API Key를 등록해 주세요."
            playbackState = "API Key 필요"
            activeTicket = nil
            navigationSpeaking = false
            activePriority = 0
            return
        }

        let selection = d.string(forKey: "voiceIdentifier") ?? ""
        let targetVoice: String
        if selection.hasPrefix("typecast:") {
            targetVoice = String(selection.dropFirst(9))
        } else if !tc.selectedVoiceId.isEmpty {
            targetVoice = tc.selectedVoiceId
        } else {
            targetVoice = TypecastClient.defaultVoiceId
        }

        _ = playTypecast(item, voiceId: targetVoice)
    }

    // MARK: - Typecast AI Playback (Unconditional & Permanent Cache)

    private func playTypecast(_ item: VoiceItem, voiceId: String? = nil) -> Bool {
        let tc = TypecastClient.shared
        guard tc.isEnabled && tc.hasKey else {
            notice = "타입캐스트 API Key를 등록해 주세요."
            playbackState = "API Key 필요"
            activeTicket = nil
            navigationSpeaking = false
            activePriority = 0
            return false
        }
        let defaults = UserDefaults.standard
        guard defaults.double(forKey: "voiceVolume") > 0 else {
            notice = "브리핑 음량이 0임"
            playbackState = "음량 0"
            return true
        }
        guard Date() < item.expires else {
            playbackState = "안내 기한 만료"
            drain()
            return true
        }

        let targetVoice = (voiceId ?? tc.selectedVoiceId).trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTarget = targetVoice.isEmpty ? TypecastClient.defaultVoiceId : targetVoice

        let ticket = UUID()
        activeTicket = ticket
        activeManual = item.manual
        lastText = item.text
        notice = ""

        // 1. Instant cache hit: play immediately (0ms, 0 credit)
        if let cachedURL = tc.cachedURL(for: item.text, voiceId: resolvedTarget) {
            playTypecastAudio(cachedURL, ticket: ticket, item: item, defaults: defaults)
            return true
        }

        // 2. Online fetch via Typecast API
        playbackState = "타입캐스트 음성 생성 중…"
        Task {
            do {
                let audioURL = try await tc.synthesize(text: item.text, voiceId: resolvedTarget)
                await MainActor.run {
                    guard self.activeTicket == ticket else { return }
                    self.playTypecastAudio(audioURL, ticket: ticket, item: item, defaults: defaults)
                }
            } catch {
                await MainActor.run {
                    guard self.activeTicket == ticket else { return }
                    self.activeTicket = nil
                    self.speaking = false
                    self.navigationSpeaking = false
                    self.activePriority = 0
                    self.notice = "타입캐스트 안내 실패: \(error.localizedDescription)"
                    self.playbackState = "합성 실패"
                    self.drain()
                }
            }
        }
        return true
    }

    private func playTypecastAudio(_ url: URL, ticket: UUID, item: VoiceItem, defaults: UserDefaults) {
        do {
            try activateAudio(defaults)
            let volume = Float(min(1, max(0, defaults.double(forKey: "voiceVolume"))))
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.volume = volume
            p.prepareToPlay()
            p.play()
            self.typecastPlayer = p
            self.speaking = true
            self.playbackState = "읽는 중 · 타입캐스트 AI 음성"
            self.refreshOutput()
        } catch {
            activeTicket = nil
            notice = "타입캐스트 오디오 재생 실패"
            playbackState = "재생 실패"
            drain()
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finishPlayback()
    }

    private func finishPlayback() {
        guard activeTicket != nil || speaking else { return }
        activeTicket = nil
        activeManual = false
        speaking = false
        navigationSpeaking = false
        activePriority = 0
        playbackState = "재생 완료"
        typecastPlayer = nil
        releaseAudio()
        quietUntil = .distantPast
        drain()
    }

    func stopAutomatic() {
        queue.clearAutomatic()
        if activeTicket != nil && !activeManual {
            cancelCurrent()
            playbackState = "중지됨"
        }
    }

    func stop() {
        queue.clear()
        cancelCurrent()
        playbackState = "중지됨"
        notice = ""
    }

    func cancelCurrent() {
        activeTicket = nil
        activeManual = false
        speaking = false
        navigationSpeaking = false
        activePriority = 0

        typecastPlayer?.stop()
        typecastPlayer = nil

        releaseAudio()
    }

    private func refreshOutput() {
        let audio = AVAudioSession.sharedInstance()
        let ports = audio.currentRoute.outputs.map { $0.portType == .builtInSpeaker ? "iPhone 스피커" : $0.portName }
        let route = ports.isEmpty ? "출력 준비 중" : ports.joined(separator: ", ")
        let description = "출력: \(route) · 기기 음량 \(Int((audio.outputVolume * 100).rounded()))%"
        if outputDescription != description {
            outputDescription = description
        }
    }

    private func releaseAudio() {
        releaseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.activeTicket == nil, self.typecastPlayer == nil, self.queue.items.isEmpty else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
        releaseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func activateAudio(_ defaults: UserDefaults) throws {
        releaseWork?.cancel()
        releaseWork = nil
        let audio = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP]
        if defaults.bool(forKey: "voiceDuck") {
            options.insert(.duckOthers)
        } else {
            options.insert(.mixWithOthers)
        }
        do {
            try audio.setCategory(.playback, mode: .spokenAudio, options: options)
        } catch {
            try? audio.setCategory(.playback, options: options)
        }
        try audio.setActive(true)
    }
}
