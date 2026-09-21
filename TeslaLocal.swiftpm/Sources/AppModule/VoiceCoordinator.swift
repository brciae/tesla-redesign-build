import SwiftUI
import AVFoundation

/// Single selected-voice output for navigation, safety and vehicle announcements.
final class VoiceCoordinator: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var speaking = false
    @Published private(set) var lastText = ""
    @Published private(set) var notice = ""
    @Published private(set) var playbackState = "대기"
    @Published private(set) var outputDescription = ""
    private let synth = AVSpeechSynthesizer()
    private let offline = OfflineSpeechEngine()
    private var offlineTicket: UUID?
    private let output = VoicePlaybackEngine()
    private let recordedPlayer = RecordedAudioPlaylistPlayer()
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
    private var activeUtterance: AVSpeechUtterance?
    private var activeManual = false
    private var requestedAt = Date.distantPast
    private var lastGuideText = ""
    private var lastGuideAt = Date.distantPast
    private var navigationSpeaking = false
    private var activePriority = 0
    override init() {
        super.init()
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "voiceSystemV28") {
            if (defaults.string(forKey: "voiceIdentifier") ?? "").hasPrefix("offline:") {
                defaults.set("", forKey: "voiceIdentifier")
                notice = "기존 합성 캐릭터 음성 제외 · iPhone 기본 음성으로 변경됨"
            }
            defaults.set(true, forKey: "voiceSystemV28")
        }
        if !defaults.bool(forKey: "voiceNaturalV19") {
            if !(defaults.string(forKey: "voiceIdentifier") ?? "").hasPrefix("offline:") { defaults.set("", forKey: "voiceIdentifier") }
            defaults.set(1.0, forKey: "voicePitch"); defaults.set(true, forKey: "voiceNaturalV19")
        }
        // Ensure default voice is the bundled recorded voice (yumi) if unset or invalid
        let currentVoice = defaults.string(forKey: "voiceIdentifier") ?? ""
        if currentVoice.isEmpty || (!currentVoice.hasPrefix(RecordedVoice.prefix) && !currentVoice.hasPrefix("offline:") && AVSpeechSynthesisVoice(identifier: currentVoice) == nil) {
            let defaultId = RecordedVoice.voices.first?.id ?? "recorded:yumi"
            defaults.set(defaultId, forKey: "voiceIdentifier")
        }
        defaults.set(true, forKey: "voiceRecordedV42")
        if defaults.object(forKey: "voiceTrip") == nil, let old = defaults.object(forKey: "briefOnArrival") as? Bool { defaults.set(old, forKey: "voiceTrip") }
        UserDefaults.standard.register(defaults: ["voiceAutomations": true, "voiceEnabled": true, "voiceConnection": true, "voiceTrip": true,
            "voiceCharge": true, "voiceBattery": true, "voiceDestination": true, "voiceControl": true,
            "voiceRate": 0.47, "voicePitch": 1.0, "voiceVolume": 0.8, "voiceQuietStart": 22,
            "voiceQuietEnd": 7, "voiceDuck": true, "navVoiceEnabled": true, "navSafetyVoice": true, "navVoiceVolume": 1.0])
        synth.delegate = self
        synth.usesApplicationAudioSession = true
        let tick = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.refreshOutput()
            if self.activeUtterance != nil && !self.speaking && Date().timeIntervalSince(self.requestedAt) > 8 {
                self.cancelCurrent(); self.playbackState = "재생 시작 실패"
                self.notice = "음성이 시작되지 않음 · iPhone의 한국어 음성 다운로드와 오디오 출력을 확인해 주세요."
            }
            self.drain()
        }
        timer = tick; RunLoop.main.add(tick, forMode: .common)
        refreshOutput()
        memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in self?.cancelCurrent(); self?.offline.release(); RecordedVoice.releaseCache() }
        routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshOutput() }
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            self.interrupted = raw == AVAudioSession.InterruptionType.began.rawValue
            if self.interrupted { self.stop(); self.notice = "통화·다른 오디오로 안내 일시 중지" }
        }
    }
    deinit { timer?.invalidate(); offline.cancel(); if let memoryObserver { NotificationCenter.default.removeObserver(memoryObserver) }; if let observer { NotificationCenter.default.removeObserver(observer) }; if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) } }
    func nativeSession(_ active: Bool) {
        // v30: the Kakao engine no longer owns the audio session; starting guidance must not cut the current sentence.
        nativeActive = false
        _ = active
        if !active {
            queue.clearNavigation()
            lastGuideText = ""; lastGuideAt = .distantPast
            nativeSpeaking = false
        }
    }
    func nativeVoice(_ active: Bool) {
        nativeSpeaking = active
        quietUntil = Date().addingTimeInterval(active ? 0 : 1.5)
        if active { cancelCurrent(); playbackState = "내비 안내 우선" }
    }
    func navigationGuide(_ text: String, safety: Bool) {
        let d = UserDefaults.standard, now = Date()
        guard !text.isEmpty, d.bool(forKey: "voiceEnabled"), d.bool(forKey: safety ? "navSafetyVoice" : "navVoiceEnabled") else { return }
        let timeSinceLast = now.timeIntervalSince(lastGuideAt)
        // 1. Never repeat identical guidance within 12 seconds
        if text == lastGuideText && timeSinceLast < 12.0 { return }
        // 2. Minimum interval between distinct navigation guidance
        if timeSinceLast < 3.5 && !safety { return }
        if safety && timeSinceLast < 2.5 { return }
        lastGuideText = text; lastGuideAt = now

        let priority = safety ? 5 : 4
        // Clear outdated navigation items from queue: a new turn or safety replaces pending items
        queue.pruneNavigation(forKey: safety ? "navigation.safety" : "navigation.turn")

        queue.add(VoiceItem(key: safety ? "navigation.safety" : "navigation.turn", text: SpeechText.prepare(text), expires: now.addingTimeInterval(8), priority: priority, manual: true), now: now)
        drain()
    }
    /// v30 studio audition: plays `profile` once without changing the saved selection.
    private var auditionProfile: VoiceProfile?
    func audition(_ profile: VoiceProfile, text: String) {
        auditionProfile = profile.validated()
        preview(text)
    }
    /// Persona of the voice that will speak next: the audition draft if one is pending, else the saved choice.
    private var activeTone: CharacterTone? {
        if let profile = auditionProfile { return profile.tone }
        guard let selection = UserDefaults.standard.string(forKey: "voiceIdentifier"), selection.hasPrefix("offline:"),
              let profile = VoiceLibrary.profile(for: String(selection.dropFirst(8))) else { return nil }
        return profile.tone
    }

    func preview(_ text: String) {
        stop()
        if interrupted { notice = "통화·다른 오디오가 끝난 뒤 미리 듣기를 다시 눌러 주세요."; return }
        notice = nativeSpeaking ? "내비 안내가 끝나면 미리 듣기 재생" : ""
        playbackState = "안내 대기 중"
        say(text, key: "preview", category: "", priority: 3, ttl: 30, manual: true)
    }
    func say(_ text: String, key: String, category: String, priority: Int = 1, ttl: TimeInterval = 15, manual: Bool = false) {
        let d = UserDefaults.standard
        guard manual || (d.bool(forKey: "voiceEnabled") && d.bool(forKey: category)) else { return }
        let now = Date()
        if !manual && d.bool(forKey: "voiceQuietEnabled") && VoiceQueue.quiet(hour: Calendar.current.component(.hour, from: now), start: d.integer(forKey: "voiceQuietStart"), end: d.integer(forKey: "voiceQuietEnd")) { return }
        // v37: the character persona rewrites the sentence endings, so a 10대 voice actually talks like one.
        let styled = BriefingStyle.selected.phrase(text, category: category)
        let spoken = activeTone?.rewrite(styled) ?? styled
        queue.add(VoiceItem(key: key, text: SpeechText.prepare(spoken), expires: now.addingTimeInterval(ttl), priority: priority, manual: manual), now: now)
        drain()
    }
    private func drain() {
        guard !interrupted, !nativeSpeaking, activeUtterance == nil, offlineTicket == nil, !synth.isSpeaking, Date() >= quietUntil else { return }
        guard let item = queue.next(now: Date()) else { return }
        navigationSpeaking = item.key.hasPrefix("navigation.")
        activePriority = item.priority
        let d = UserDefaults.standard
        if navigationSpeaking && (!d.bool(forKey: "voiceEnabled") || !d.bool(forKey: item.key == "navigation.safety" ? "navSafetyVoice" : "navVoiceEnabled")) {
            navigationSpeaking = false; activePriority = 0
            drain(); return
        }
        guard item.manual || d.bool(forKey: "voiceEnabled") else { return }
        if !item.manual && d.bool(forKey: "voiceQuietEnabled") && VoiceQueue.quiet(hour: Calendar.current.component(.hour, from: Date()), start: d.integer(forKey: "voiceQuietStart"), end: d.integer(forKey: "voiceQuietEnd")) { return }
        if item.key == "preview", let profile = auditionProfile {
            auditionProfile = nil
            playOffline(item, profile: profile); return
        }
        // v42: the recorded guidance voice. When the recordings cover the sentence they are played as-is;
        // anything they do not cover falls through to the engine so nothing is ever left unsaid.
        if let selection = d.string(forKey: "voiceIdentifier"), selection.hasPrefix(RecordedVoice.prefix) {
            if playRecorded(item, voice: selection) { return }
            if VoicePackManifest.installed, let profile = VoiceLibrary.profile(for: RecordedVoice.fallbackProfileID) {
                playOffline(item, profile: profile); return
            }
        }
        if let selection = d.string(forKey: "voiceIdentifier"), selection.hasPrefix("offline:") {
            guard let profile = VoiceLibrary.profile(for: String(selection.dropFirst(8))) else { notice = "음성 선택 확인 필요"; return }
            playOffline(item, profile: profile); return
        }
        let utterance = AVSpeechUtterance(string: item.text)
        let selectedVoice = d.string(forKey: "voiceIdentifier") ?? ""
        let fallbackVoice = Self.yunaVoice()
        if selectedVoice.hasPrefix(RecordedVoice.prefix) || selectedVoice.hasPrefix("offline:") {
            utterance.voice = fallbackVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(identifier: selectedVoice) ?? fallbackVoice
        }
        utterance.rate = min(0.6, max(0.3, Float(d.double(forKey: "voiceRate")) * BriefingStyle.selected.rateMultiplier))
        utterance.postUtteranceDelay = BriefingStyle.selected.pause
        utterance.pitchMultiplier = 1.0
        utterance.volume = Float(min(1, max(0, d.double(forKey: "voiceVolume"))))
        guard utterance.volume > 0 else { notice = "브리핑 음량이 0임 · 음량을 올린 뒤 미리 듣기를 눌러 주세요."; playbackState = "음량 0"; return }
        guard utterance.voice != nil else { notice = "한국어 음성을 찾지 못함 · iPhone 설정에서 한국어 음성을 내려받아 주세요."; playbackState = "음성 없음"; return }
        do {
            // Do not replace the SDK audio category while native guidance owns the session.
            try activateAudio(d)
            lastText = item.text; notice = ""; playbackState = "재생 준비 중"
            activeUtterance = utterance; activeManual = item.manual; requestedAt = Date()
            refreshOutput(); synth.speak(utterance)
        } catch {
            if navigationSpeaking { lastGuideText = ""; lastGuideAt = .distantPast }
            notice = "음성 출력 준비 실패 · 오디오 연결 확인 필요"; playbackState = "재생 실패"; cancelCurrent()
        }
    }
    /// BLE disconnects invalidate automatic vehicle announcements, not a manual voice test.
    func stopAutomatic() {
        queue.clearAutomatic()
        if (activeUtterance != nil || offlineTicket != nil) && !activeManual { cancelCurrent(); playbackState = "중지됨" }
    }
    func stop() { queue.clear(); auditionProfile = nil; cancelCurrent(); playbackState = "중지됨"; notice = "" }
    private func cancelCurrent() {
        // Clear ownership before stopSpeaking: an old didCancel must not stop the next utterance.
        activeUtterance = nil; activeManual = false; speaking = false
        navigationSpeaking = false
        activePriority = 0
        offlineTicket = nil; offline.cancel(); output.stop()
        recordedPlayer.stop()
        synth.stopSpeaking(at: .immediate); releaseAudio()
    }
    private func refreshOutput() {
        let audio = AVAudioSession.sharedInstance()
        let ports = audio.currentRoute.outputs.map { $0.portType == .builtInSpeaker ? "iPhone 스피커" : $0.portName }
        let route = ports.isEmpty ? "출력 준비 중" : ports.joined(separator: ", ")
        let description = "출력: \(route) · 기기 음량 \(Int((audio.outputVolume * 100).rounded()))%"
        if outputDescription != description { outputDescription = description }
    }
    /// v30: deactivate a moment later so back-to-back announcements do not un-duck/re-duck music (audible pumping).
    private func releaseAudio() {
        releaseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            // Guard against deactivating audio while queued items are pending or speech is active
            guard let self, self.activeUtterance == nil, self.offlineTicket == nil, !self.synth.isSpeaking, self.queue.items.isEmpty else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
        releaseWork = work
        // 2.5s window ensures inter-utterance pauses (1.2s) never cause audible music volume pumping
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }
    private func activateAudio(_ defaults: UserDefaults) throws {
        releaseWork?.cancel(); releaseWork = nil
        let audio = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP]
        if defaults.bool(forKey: "voiceDuck") { options.insert(.duckOthers) } else { options.insert(.mixWithOthers) }
        do {
            try audio.setCategory(.playback, mode: .voicePrompt, options: options)
        } catch {
            do {
                try audio.setCategory(.playback, options: options)
            } catch {
                try? audio.setCategory(.playback)
            }
        }
        do {
            try audio.setActive(true)
        } catch {
            try? audio.setActive(true, options: [])
        }
    }
    static func yunaVoice() -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix("ko") && !$0.voiceTraits.contains(.isNoveltyVoice) && ($0.name.localizedCaseInsensitiveContains("yuna") || $0.identifier.localizedCaseInsensitiveContains("yuna"))
        }.sorted { $0.quality.rawValue > $1.quality.rawValue }.first ?? AVSpeechSynthesisVoice(language: "ko-KR")
    }
    /// Plays the pre-recorded clips for `item`. Returns false when the recordings do not cover the text,
    /// so the caller can fall back to the engine; true means playback was started (or failed loudly).
    private func playRecorded(_ item: VoiceItem, voice identifier: String) -> Bool {
        guard let plan = RecordedVoice.plan(for: item.text, voice: identifier), !plan.isEmpty else { return false }
        let defaults = UserDefaults.standard
        guard defaults.double(forKey: "voiceVolume") > 0 else { notice = "브리핑 음량이 0임"; playbackState = "음량 0"; return true }
        guard Date() < item.expires else { playbackState = "안내 기한 만료"; drain(); return true }
        let ticket = UUID(); offlineTicket = ticket; activeManual = item.manual
        lastText = item.text; notice = ""
        do {
            try activateAudio(defaults)
            let volume = Float(min(1, max(0, defaults.double(forKey: "voiceVolume"))))
            speaking = true; playbackState = "읽는 중 · 녹음 음성"; refreshOutput()
            recordedPlayer.play(steps: plan, volume: volume) { [weak self] in
                guard let self, self.offlineTicket == ticket else { return }
                self.offlineTicket = nil; self.activeManual = false; self.speaking = false
                self.navigationSpeaking = false; self.activePriority = 0
                self.playbackState = "재생 완료"; self.releaseAudio()
                // Natural 0.25s breathing gap before the next queued guidance
                self.quietUntil = Date().addingTimeInterval(0.25)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.drain()
                }
            }
        } catch {
            if navigationSpeaking { lastGuideText = ""; lastGuideAt = .distantPast }
            cancelCurrent(); playbackState = "오디오 출력 실패"
            notice = "오디오 출력 준비 실패 · 블루투스·볼륨 확인 후 다시 시도"
        }
        return true
    }
    private func playOffline(_ item: VoiceItem, profile: VoiceProfile) {
        let defaults = UserDefaults.standard
        guard defaults.double(forKey: "voiceVolume") > 0 else { notice = "브리핑 음량이 0임"; playbackState = "음량 0"; return }
        guard Date() < item.expires else { playbackState = "안내 기한 만료"; drain(); return }
        let ticket = UUID(); offlineTicket = ticket; activeManual = item.manual
        lastText = item.text; notice = ""; playbackState = "아이폰에서 음성 합성 중"
        var started = false
        // v32: hold the first sentences until there is enough audio to play through. Starting on the
        // first chunk let playback catch up with synthesis and cut a word in half mid-announcement.
        var buffered: [OfflineSpeechEngine.Chunk] = []
        var bufferedSeconds = 0.0
        let leadSeconds = 1.6
        let rate = Float(defaults.double(forKey: "voiceRate") / 0.47) * BriefingStyle.selected.rateMultiplier
        offline.synthesize(text: item.text, profile: profile, rate: rate, onChunk: { [weak self] chunk in
            guard let self, self.offlineTicket == ticket, !self.interrupted else { return }
            do {
                if !started {
                    buffered.append(chunk)
                    bufferedSeconds += Double(chunk.samples.count) / Double(max(1, chunk.sampleRate)) + chunk.gap
                    guard bufferedSeconds >= leadSeconds else { return }
                    try self.activateAudio(defaults)
                    try self.output.begin(sampleRate: chunk.sampleRate) { [weak self] in
                        guard let self, self.offlineTicket == ticket else { return }
                        self.offlineTicket = nil; self.activeManual = false; self.speaking = false
                        self.navigationSpeaking = false; self.activePriority = 0
                        self.playbackState = "재생 완료"; self.releaseAudio(); self.drain()
                    }
                    self.output.volume = Float(min(1, max(0, defaults.double(forKey: "voiceVolume"))))
                    started = true
                    self.speaking = true; self.playbackState = "읽는 중 · 오프라인 AI 음성"; self.refreshOutput()
                    for pending in buffered { self.output.schedule(pending.samples, gap: pending.gap) }
                    buffered = []
                    return
                }
                self.output.schedule(chunk.samples, gap: chunk.gap)
            } catch {
                self.cancelCurrent(); self.playbackState = "오디오 출력 실패"
                self.notice = "오디오 출력 준비 실패 · 블루투스·볼륨 확인 후 다시 시도"
            }
        }, completion: { [weak self] result in
            guard let self, self.offlineTicket == ticket else { return }
            switch result {
            case .success:
                // Short announcement: everything is still buffered, so start and play it in one go.
                if !started, !buffered.isEmpty, let first = buffered.first {
                    do {
                        try self.activateAudio(UserDefaults.standard)
                        try self.output.begin(sampleRate: first.sampleRate) { [weak self] in
                            guard let self, self.offlineTicket == ticket else { return }
                            self.offlineTicket = nil; self.activeManual = false; self.speaking = false
                            self.navigationSpeaking = false; self.activePriority = 0
                            self.playbackState = "재생 완료"; self.releaseAudio(); self.drain()
                        }
                        self.output.volume = Float(min(1, max(0, UserDefaults.standard.double(forKey: "voiceVolume"))))
                        started = true
                        self.speaking = true; self.playbackState = "읽는 중 · 오프라인 AI 음성"; self.refreshOutput()
                        for pending in buffered { self.output.schedule(pending.samples, gap: pending.gap) }
                        buffered = []
                    } catch {
                        self.cancelCurrent(); self.playbackState = "오디오 출력 실패"
                        self.notice = "오디오 출력 준비 실패 · 블루투스·볼륨 확인 후 다시 시도"
                        return
                    }
                }
                if started { self.output.endInput() } else { self.offlineTicket = nil; self.drain() }
            case .failure(let error):
                if error is CancellationError { return }
                if self.navigationSpeaking { self.lastGuideText = ""; self.lastGuideAt = .distantPast }
                if started { self.output.endInput() } else {
                    self.cancelCurrent(); self.playbackState = "오프라인 음성 실패"
                    self.notice = "음성팩 다운로드·저장 공간 확인 필요. iPhone 음성을 선택하면 기본 안내를 사용할 수 있음."
                }
            }
        })
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        guard activeUtterance === utterance else { return }; speaking = true; playbackState = "읽는 중"
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard activeUtterance === utterance else { return }
        navigationSpeaking = false; activePriority = 0
        activeUtterance = nil; activeManual = false; speaking = false; playbackState = "재생 완료"; releaseAudio()
        quietUntil = Date().addingTimeInterval(1.2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.drain()
        }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard activeUtterance === utterance else { return }
        activeUtterance = nil; activeManual = false; speaking = false; playbackState = "중지됨"; releaseAudio()
    }
}
