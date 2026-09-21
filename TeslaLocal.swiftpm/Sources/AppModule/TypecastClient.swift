import Foundation
import AVFoundation
import CryptoKit

/// Client and local cache manager for Typecast (타입캐스트) AI Text-to-Speech API.
/// Supports monthly 15,000 free credits with aggressive local disk caching
/// to achieve zero-credit re-use and instantaneous (0ms) offline replay.
final class TypecastClient: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = TypecastClient()

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "typecastEnabled") }
    }
    // Up to 5 Typecast accounts (each 15,000 free credits = 75,000 credits total per month)
    @Published var apiKeys: [String] {
        didSet {
            UserDefaults.standard.set(apiKeys, forKey: "typecastApiKeys")
            if let first = apiKeys.first {
                UserDefaults.standard.set(first.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "typecastApiKey")
            }
        }
    }
    @Published var activeKeyIndex: Int {
        didSet { UserDefaults.standard.set(activeKeyIndex, forKey: "typecastActiveKeyIndex") }
    }
    @Published var selectedVoiceId: String {
        didSet {
            let clean = selectedVoiceId.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(clean.isEmpty ? Self.defaultVoiceId : clean, forKey: "typecastVoiceId")
        }
    }
    @Published var complementRecordedVoices: Bool {
        didSet { UserDefaults.standard.set(complementRecordedVoices, forKey: "typecastComplementRecorded") }
    }
    @Published var voiceIdYumi: String {
        didSet {
            let clean = voiceIdYumi.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(clean, forKey: "typecastVoiceId_yumi")
        }
    }
    @Published var voiceIdHyeonji: String {
        didSet {
            let clean = voiceIdHyeonji.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(clean, forKey: "typecastVoiceId_hyeonji")
        }
    }
    @Published var voiceIdSubin: String {
        didSet {
            let clean = voiceIdSubin.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(clean, forKey: "typecastVoiceId_subin")
        }
    }
    @Published var voiceIdSeohee: String {
        didSet {
            let clean = voiceIdSeohee.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(clean, forKey: "typecastVoiceId_seohee")
        }
    }
    @Published var isSynthesizing = false
    @Published var lastStatus = ""
    @Published var cacheFileCount = 0

    var apiKey: String {
        get { activeApiKey }
        set {
            if !apiKeys.isEmpty {
                apiKeys[0] = newValue
            } else {
                apiKeys = [newValue, "", "", "", ""]
            }
        }
    }

    var validApiKeys: [String] {
        apiKeys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var activeApiKey: String {
        let valid = validApiKeys
        guard !valid.isEmpty else { return "" }
        let idx = min(max(0, activeKeyIndex), valid.count - 1)
        return valid[idx]
    }

    func switchToNextKey() -> Bool {
        let valid = validApiKeys
        guard valid.count > 1 else { return false }
        activeKeyIndex = (activeKeyIndex + 1) % valid.count
        lastStatus = "다음 API 계정(\(activeKeyIndex + 1)/\(valid.count))으로 수동 전환됨"
        return true
    }

    static let defaultVoiceId = "은경"

    // 4 Curated Presets requested by user: 은경, 서현, 아엘, 한영
    static let presetVoices: [(name: String, id: String, desc: String)] = [
        ("은경", "은경", "차분하고 편안한 중음 톤 · 사연/브이로그"),
        ("서현", "서현", "또렷하고 신뢰감 있는 아나운서 톤"),
        ("아엘", "아엘", "감성적이고 자연스러운 대화 톤"),
        ("한영", "한영", "표현력이 풍부하고 생생한 대화 톤")
    ]

    private var resolvedVoiceIds: [String: String] = [:]

    private var player: AVAudioPlayer?
    private var testCompletion: (() -> Void)?

    private var cacheDirectory: URL {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("TypecastAudioCache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    override init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "typecastEnabled")
        if let savedKeys = UserDefaults.standard.stringArray(forKey: "typecastApiKeys"), !savedKeys.isEmpty {
            var keys = savedKeys
            while keys.count < 5 { keys.append("") }
            self.apiKeys = Array(keys.prefix(5))
        } else {
            let legacyKey = UserDefaults.standard.string(forKey: "typecastApiKey") ?? ""
            self.apiKeys = [legacyKey, "", "", "", ""]
        }
        self.activeKeyIndex = UserDefaults.standard.integer(forKey: "typecastActiveKeyIndex")
        self.selectedVoiceId = UserDefaults.standard.string(forKey: "typecastVoiceId") ?? Self.defaultVoiceId
        self.complementRecordedVoices = UserDefaults.standard.object(forKey: "typecastComplementRecorded") == nil ? true : UserDefaults.standard.bool(forKey: "typecastComplementRecorded")
        self.voiceIdYumi = UserDefaults.standard.string(forKey: "typecastVoiceId_yumi") ?? "유미"
        self.voiceIdHyeonji = UserDefaults.standard.string(forKey: "typecastVoiceId_hyeonji") ?? "현지"
        self.voiceIdSubin = UserDefaults.standard.string(forKey: "typecastVoiceId_subin") ?? "수빈"
        self.voiceIdSeohee = UserDefaults.standard.string(forKey: "typecastVoiceId_seohee") ?? "서희"
        super.init()
        updateCacheCount()
    }

    func voiceIdForRecorded(identifier: String) -> String {
        let key = identifier.replacingOccurrences(of: RecordedVoice.prefix, with: "")
        switch key {
        case "yumi": return voiceIdYumi.isEmpty ? "유미" : voiceIdYumi
        case "hyeonji": return voiceIdHyeonji.isEmpty ? "현지" : voiceIdHyeonji
        case "subin": return voiceIdSubin.isEmpty ? "수빈" : voiceIdSubin
        case "seohee": return voiceIdSeohee.isEmpty ? "서희" : voiceIdSeohee
        default: return selectedVoiceId
        }
    }

    func resolveVoiceId(for input: String) async -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Self.defaultVoiceId }

        // Explicit Typecast ID format (e.g., tc_..., uc_..., or hex format)
        if trimmed.hasPrefix("tc_") || trimmed.hasPrefix("uc_") || trimmed.count >= 24 {
            return trimmed
        }

        if let cached = resolvedVoiceIds[trimmed] {
            return cached
        }

        guard hasKey else { return trimmed }

        // Dynamic lookup from Typecast /v2/voices API using current active API key
        if let url = URL(string: "https://api.typecast.ai/v2/voices") {
            var request = URLRequest(url: url)
            request.setValue(activeApiKey, forHTTPHeaderField: "X-API-KEY")
            request.timeoutInterval = 8.0

            if let (data, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for item in json {
                    let vId = item["voice_id"] as? String ?? ""
                    let vName = item["voice_name"] as? String ?? ""
                    let vKoName = item["name"] as? String ?? ""
                    if !vId.isEmpty && (vName.localizedCaseInsensitiveContains(trimmed) || vKoName.localizedCaseInsensitiveContains(trimmed)) {
                        resolvedVoiceIds[trimmed] = vId
                        return vId
                    }
                }
            }
        }

        return trimmed
    }

    var hasKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Cache Management

    private func cacheKey(for text: String, voiceId: String) -> String {
        let input = "\(voiceId)_\(text)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func cachedURL(for text: String, voiceId: String) -> URL? {
        let key = cacheKey(for: text, voiceId: voiceId)
        let fileURL = cacheDirectory.appendingPathComponent("\(key).wav")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        return nil
    }

    private func saveToCache(data: Data, for text: String, voiceId: String) -> URL? {
        let key = cacheKey(for: text, voiceId: voiceId)
        let fileURL = cacheDirectory.appendingPathComponent("\(key).wav")
        do {
            try data.write(to: fileURL)
            updateCacheCount()
            return fileURL
        } catch {
            return nil
        }
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        updateCacheCount()
        lastStatus = "캐시가 모두 삭제되었습니다."
    }

    private func updateCacheCount() {
        if let files = try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path) {
            cacheFileCount = files.count
        } else {
            cacheFileCount = 0
        }
    }

    // MARK: - API Speech Synthesis

    /// Synthesizes speech via Typecast API or returns immediately from local disk cache.
    func synthesize(text: String, voiceId: String? = nil) async throws -> URL {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            throw NSError(domain: "Typecast", code: 400, userInfo: [NSLocalizedDescriptionKey: "음성 변환할 텍스트가 비어 있습니다."])
        }

        let targetVoice = (voiceId ?? selectedVoiceId).trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedVoice = await resolveVoiceId(for: targetVoice.isEmpty ? Self.defaultVoiceId : targetVoice)

        // 1. Instant Cache Hit (0 credits, 0ms latency)
        if let cached = cachedURL(for: cleanText, voiceId: resolvedVoice) {
            return cached
        }

        // 2. Online Synthesis with Multi-Account Sequential Rollover (최대 5개 계정 순차 소진)
        let keysToTry = validApiKeys
        guard !keysToTry.isEmpty else {
            throw NSError(domain: "Typecast", code: 401, userInfo: [NSLocalizedDescriptionKey: "타입캐스트 API Key가 등록되지 않았습니다."])
        }

        await MainActor.run { isSynthesizing = true }
        defer { Task { @MainActor in isSynthesizing = false } }

        guard let apiURL = URL(string: "https://api.typecast.ai/v1/text-to-speech") else {
            throw NSError(domain: "Typecast", code: 500, userInfo: [NSLocalizedDescriptionKey: "API URL 생성 실패"])
        }

        let startIdx = min(max(0, activeKeyIndex), keysToTry.count - 1)
        var lastErrorMsg = ""

        // Try from current active account to subsequent accounts sequentially
        for offset in 0..<keysToTry.count {
            let currentTryIdx = (startIdx + offset) % keysToTry.count
            let key = keysToTry[currentTryIdx]

            var request = URLRequest(url: apiURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(key, forHTTPHeaderField: "X-API-KEY")
            request.timeoutInterval = 12.0

            let body: [String: Any] = [
                "voice_id": resolvedVoice,
                "text": cleanText,
                "model": "ssfm-v30",
                "prompt": [
                    "emotion_type": "smart"
                ],
                "output": [
                    "audio_format": "wav",
                    "volume": 100
                ]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    lastErrorMsg = "서버 응답 없음"
                    continue
                }

                if httpResponse.statusCode == 200 {
                    // Success! If we shifted to a new key, update activeKeyIndex
                    if self.activeKeyIndex != currentTryIdx {
                        await MainActor.run {
                            self.activeKeyIndex = currentTryIdx
                            self.lastStatus = "계정 \(currentTryIdx + 1)번으로 자동 전환 및 정상 합성 완료"
                        }
                    }
                    guard let savedURL = saveToCache(data: data, for: cleanText, voiceId: resolvedVoice) else {
                        throw NSError(domain: "Typecast", code: 500, userInfo: [NSLocalizedDescriptionKey: "오디오 캐시 저장 실패"])
                    }
                    return savedURL
                }

                // Check for credit exhaustion or rate limit
                let respStr = String(data: data, encoding: .utf8) ?? ""
                let isCreditError = httpResponse.statusCode == 402 || httpResponse.statusCode == 429 ||
                                   respStr.localizedCaseInsensitiveContains("credit") ||
                                   respStr.localizedCaseInsensitiveContains("quota") ||
                                   respStr.localizedCaseInsensitiveContains("limit") ||
                                   respStr.localizedCaseInsensitiveContains("insufficient") ||
                                   httpResponse.statusCode == 403

                if isCreditError && keysToTry.count > 1 {
                    await MainActor.run {
                        self.lastStatus = "계정 \(currentTryIdx + 1)번 크레딧 소진 → 다음 계정(\((currentTryIdx + 1) % keysToTry.count + 1)번)으로 자동 전환 중…"
                    }
                    lastErrorMsg = "계정 \(currentTryIdx + 1) 소진"
                    continue // Try next key in pool!
                } else {
                    lastErrorMsg = "HTTP \(httpResponse.statusCode): \(respStr)"
                }
            } catch {
                lastErrorMsg = error.localizedDescription
                continue
            }
        }

        throw NSError(domain: "Typecast", code: 402, userInfo: [NSLocalizedDescriptionKey: "모든 타입캐스트 계정 크레딧 소진 또는 호출 실패: \(lastErrorMsg)"])
    }

    // MARK: - Test Preview Playback

    func testSpeech(text: String = "안녕하세요! 테슬라 스마트 드라이빙을 시작합니다.", voiceId: String? = nil, completion: (() -> Void)? = nil) {
        stop()
        testCompletion = completion
        lastStatus = "타입캐스트 음성 생성 중…"

        Task {
            do {
                let audioURL = try await synthesize(text: text, voiceId: voiceId)
                await MainActor.run {
                    do {
                        let audioSession = AVAudioSession.sharedInstance()
                        try? audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                        try? audioSession.setActive(true)

                        let p = try AVAudioPlayer(contentsOf: audioURL)
                        p.delegate = self
                        p.prepareToPlay()
                        p.play()
                        self.player = p
                        self.lastStatus = "타입캐스트 음성 재생 중"
                    } catch {
                        self.lastStatus = "오디오 재생 실패: \(error.localizedDescription)"
                        completion?()
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastStatus = "합성 실패: \(error.localizedDescription)"
                    completion?()
                }
            }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        testCompletion?()
        testCompletion = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        lastStatus = "재생 완료"
        testCompletion?()
        testCompletion = nil
    }
}
