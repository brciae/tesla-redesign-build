import Foundation
import AVFoundation
import CryptoKit

/// Client and local cache manager for Typecast (타입캐스트) AI Text-to-Speech API.
/// Reuses Typecast-generated audio from the local cache.
final class TypecastClient: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = TypecastClient()

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "typecastEnabled") }
    }
    // Saved API keys; selection is manual and errors never trigger account cycling.
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
    @Published var isSynthesizing = false
    @Published var lastStatus = ""
    @Published var connectionStatus = ""
    @Published var isCheckingConnection = false
    @Published var cacheFileCount = 0
    @Published var cacheTotalSizeMB: Double = 0.0
    @Published var voiceCatalog: [String: String] = [:]

    var apiKey: String {
        get { activeApiKey }
        set {
            if apiKeys.indices.contains(activeKeyIndex) {
                apiKeys[activeKeyIndex] = newValue
            } else {
                apiKeys.append(newValue)
                activeKeyIndex = apiKeys.count - 1
            }
        }
    }

    var validApiKeys: [String] {
        apiKeys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var activeApiKey: String {
        guard apiKeys.indices.contains(activeKeyIndex) else { return "" }
        return apiKeys[activeKeyIndex].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var selectedKeyDescription: String {
        guard !activeApiKey.isEmpty else { return "사용할 API 키를 선택하세요" }
        return keyDescription(activeApiKey, index: activeKeyIndex)
    }

    private func keyDescription(_ key: String, index: Int) -> String {
        let fingerprint = SHA256.hash(data: Data(key.utf8)).prefix(4)
            .map { String(format: "%02x", $0) }.joined()
        return "키 \(index + 1)번 · 식별값 \(fingerprint)"
    }

    @MainActor
    func checkConnection() async {
        guard !isCheckingConnection else { return }
        let key = activeApiKey
        guard !key.isEmpty else { connectionStatus = "검사할 API 키를 선택하세요"; return }
        let identity = "검사 당시 " + keyDescription(key, index: activeKeyIndex)
        isCheckingConnection = true
        defer { isCheckingConnection = false }
        connectionStatus = "\(identity) · API 목록 요청 중…"
        do {
            let catalog = try await fetchVoiceCatalog(apiKey: key)
            connectionStatus = "\(identity) · GET /v3/voices · HTTP 200 · 보이스 \(Set(catalog.values).count)개. 목록 인증만 확인됨. 음성 합성 권한은 별도 확인 필요."
        } catch {
            connectionStatus = "\(identity) · GET /v3/voices · \(error.localizedDescription)"
        }
    }

    func addAccount() { apiKeys.append("") }

    func removeAccount(at index: Int) {
        guard apiKeys.indices.contains(index), apiKeys.count > 1 else { return }
        apiKeys.remove(at: index)
        if index < activeKeyIndex { activeKeyIndex -= 1 }
        else if index == activeKeyIndex { activeKeyIndex = -1 }
    }

    func switchToNextKey() -> Bool {
        let indices = apiKeys.indices.filter { !apiKeys[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !indices.isEmpty else { return false }
        activeKeyIndex = indices.first(where: { $0 > activeKeyIndex }) ?? indices[0]
        lastStatus = "API 키 \(activeKeyIndex + 1)번으로 수동 전환됨"
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

    private var player: AVAudioPlayer?
    private var testCompletion: (() -> Void)?

    // Permanent local disk storage: files in Application Support are NEVER purged by iOS
    private var cacheDirectory: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("YLCompanion/TypecastAudioCache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func migrateLegacyCacheIfNeeded() {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let legacyDir = paths[0].appendingPathComponent("TypecastAudioCache", isDirectory: true)
        guard FileManager.default.fileExists(atPath: legacyDir.path),
              let files = try? FileManager.default.contentsOfDirectory(atPath: legacyDir.path) else { return }
        let targetDir = cacheDirectory
        for file in files {
            let src = legacyDir.appendingPathComponent(file)
            let dst = targetDir.appendingPathComponent(file)
            if !FileManager.default.fileExists(atPath: dst.path) {
                try? FileManager.default.moveItem(at: src, to: dst)
            }
        }
        // A failed move must never delete the only remaining audio copy.
        if let remaining = try? FileManager.default.contentsOfDirectory(atPath: legacyDir.path), remaining.isEmpty {
            try? FileManager.default.removeItem(at: legacyDir)
        }
    }

    override init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "typecastEnabled") != nil ? UserDefaults.standard.bool(forKey: "typecastEnabled") : true
        if let savedKeys = UserDefaults.standard.stringArray(forKey: "typecastApiKeys"), !savedKeys.isEmpty {
            self.apiKeys = savedKeys
        } else {
            let legacyKey = UserDefaults.standard.string(forKey: "typecastApiKey") ?? ""
            self.apiKeys = [legacyKey]
        }
        self.activeKeyIndex = UserDefaults.standard.integer(forKey: "typecastActiveKeyIndex")
        self.selectedVoiceId = UserDefaults.standard.string(forKey: "typecastVoiceId") ?? Self.defaultVoiceId
        if let catalogData = UserDefaults.standard.data(forKey: "typecastVoiceCatalog"),
           let dict = try? JSONDecoder().decode([String: String].self, from: catalogData) {
            self.voiceCatalog = dict
        }
        super.init()
        removeLegacyOfflineData()
        migrateLegacyCacheIfNeeded()
        updateCacheCount()
        if hasKey && voiceCatalog.isEmpty {
            Task { await refreshVoiceCatalog() }
        }
    }

    // MARK: - Voice Catalog & Parsing

    private func removeLegacyOfflineData() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "voiceCustomProfiles")
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        // Only the retired downloaded model pack; retain Typecast-generated audio.
        let legacy = support.appendingPathComponent("YLCompanion/VoicePack", isDirectory: true)
        if fm.fileExists(atPath: legacy.path) {
            do { try fm.removeItem(at: legacy) }
            catch { lastStatus = "이전 오프라인 음성팩 삭제 실패: \(error.localizedDescription)" }
        }
    }

    func parseVoices(from data: Data) -> [String: String] {
        var result: [String: String] = [:]
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return result }

        let list: [[String: Any]]
        if let array = json as? [[String: Any]] {
            list = array
        } else if let dict = json as? [String: Any],
                  let array = (dict["result"] ?? dict["voices"] ?? dict["data"]) as? [[String: Any]] {
            list = array
        } else {
            return result
        }

        for item in list {
            guard let voiceId = (item["voice_id"] ?? item["actor_id"] ?? item["id"]) as? String, TypecastAPIPolicy.isVoiceID(voiceId) else {
                continue
            }

            var names: [String] = []
            if let vNameStr = item["voice_name"] as? String {
                names.append(vNameStr)
            } else if let vNameDict = item["voice_name"] as? [String: Any] {
                for v in vNameDict.values {
                    if let s = v as? String { names.append(s) }
                }
            }

            if let nameStr = item["name"] as? String {
                names.append(nameStr)
            } else if let nameDict = item["name"] as? [String: Any] {
                for v in nameDict.values {
                    if let s = v as? String { names.append(s) }
                }
            }

            if let actorStr = item["actor_name"] as? String {
                names.append(actorStr)
            }

            for name in names {
                let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty {
                    result[clean.lowercased()] = voiceId
                    result[clean.replacingOccurrences(of: " ", with: "").lowercased()] = voiceId
                }
            }
            result[voiceId.lowercased()] = voiceId
            if voiceId.hasPrefix("tc_") { result[String(voiceId.dropFirst(3)).lowercased()] = voiceId }
        }
        return result
    }

    private func fetchVoiceCatalog(apiKey: String) async throws -> [String: String] {
        let url = URL(string: "https://api.typecast.ai/v3/voices?model=ssfm-v30")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            throw TypecastAPIPolicy.failure(status: http.statusCode, data: data, secrets: [apiKey])
        }
        let catalog = parseVoices(from: data)
        guard !catalog.isEmpty else {
            throw NSError(domain: "Typecast", code: 502, userInfo: [NSLocalizedDescriptionKey: "HTTP 200이지만 지원 보이스 목록을 해석할 수 없음"])
        }
        return catalog
    }

    func refreshVoiceCatalog() async {
        guard hasKey else { return }
        do {
            let catalog = try await fetchVoiceCatalog(apiKey: activeApiKey)
            await MainActor.run {
                self.voiceCatalog = catalog
                self.lastStatus = "API 보이스 목록 동기화 완료"
            }
        } catch {
            await MainActor.run { self.lastStatus = error.localizedDescription }
        }
    }

    private func resolveVoiceId(for input: String, apiKey: String) async throws -> String {
        // Fresh account/model-scoped metadata is authoritative. Never guess a prefix,
        // use a recommendation as an exact match, or silently select another voice.
        let catalog = try await fetchVoiceCatalog(apiKey: apiKey)
        var candidates = [input]
        if let character = TypecastCatalog.find(input) {
            candidates += [character.id, character.nameKo, character.nameEn]
        }
        guard let id = TypecastAPIPolicy.resolve(candidates, in: catalog) else {
            throw NSError(domain: "Typecast", code: 404, userInfo: [NSLocalizedDescriptionKey:
                "선택한 음성을 현재 계정의 ssfm-v30 API 목록에서 찾을 수 없음. API 지원 음성 확인 필요"])
        }
        await MainActor.run { self.voiceCatalog = catalog }
        return id
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
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = cacheKey(for: clean, voiceId: voiceId)
        let fileURL = cacheDirectory.appendingPathComponent("\(key).wav")
        if isFileValid(fileURL) { return fileURL }

        // Also check mapped alias / resolved voice ID
        let lower = voiceId.lowercased()
        let noSpaces = lower.replacingOccurrences(of: " ", with: "")
        if let mapped = voiceCatalog[lower] ?? voiceCatalog[noSpaces], mapped != voiceId {
            let mappedKey = cacheKey(for: clean, voiceId: mapped)
            let mappedURL = cacheDirectory.appendingPathComponent("\(mappedKey).wav")
            if isFileValid(mappedURL) { return mappedURL }
        }
        return nil
    }

    private func isFileValid(_ url: URL) -> Bool {
        if FileManager.default.fileExists(atPath: url.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? UInt64, size > 100 {
            return true
        }
        return false
    }

    private func saveToCache(data: Data, for text: String, voiceId: String, alias: String? = nil) -> URL? {
        guard data.count > 100 else { return nil }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = cacheKey(for: clean, voiceId: voiceId)
        let fileURL = cacheDirectory.appendingPathComponent("\(key).wav")
        do {
            try data.write(to: fileURL, options: .atomic)
            if let alias, !alias.isEmpty, alias != voiceId {
                let aliasKey = cacheKey(for: clean, voiceId: alias)
                let aliasURL = cacheDirectory.appendingPathComponent("\(aliasKey).wav")
                try? data.write(to: aliasURL, options: .atomic)
            }
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
            var totalBytes: UInt64 = 0
            for file in files {
                let filePath = cacheDirectory.appendingPathComponent(file).path
                if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
                   let size = attrs[.size] as? UInt64 {
                    totalBytes += size
                }
            }
            cacheTotalSizeMB = Double(totalBytes) / (1024.0 * 1024.0)
        } else {
            cacheFileCount = 0
            cacheTotalSizeMB = 0.0
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
        let voiceInput = targetVoice.isEmpty ? Self.defaultVoiceId : targetVoice

        // 1. Instant Cache Hit (0 credits, 0ms latency)
        if let cached = cachedURL(for: cleanText, voiceId: voiceInput) {
            await MainActor.run { self.lastStatus = "저장된 타입캐스트 음성 사용 · API 연결은 별도 검사 필요" }
            return cached
        }

        // 2. Synthesize using exactly the manually selected key.
        let selectedKey = activeApiKey
        let keysToTry = selectedKey.isEmpty ? [] : [selectedKey]
        guard !keysToTry.isEmpty else {
            throw NSError(domain: "Typecast", code: 401, userInfo: [NSLocalizedDescriptionKey: "타입캐스트 API Key가 등록되지 않았습니다."])
        }

        await MainActor.run { isSynthesizing = true }
        defer { Task { @MainActor in isSynthesizing = false } }

        guard let apiURL = URL(string: "https://api.typecast.ai/v1/text-to-speech") else {
            throw NSError(domain: "Typecast", code: 500, userInfo: [NSLocalizedDescriptionKey: "API URL 생성 실패"])
        }

        let selectedIndex = activeKeyIndex
        var failures: [String] = []
        var lastFailure: NSError?

        // This list contains only the selected key. No fallback credentials.
        for key in keysToTry {
            let currentTryIdx = selectedIndex

            do {
                try Task.checkCancellation()
                let resolvedVoice = try await resolveVoiceId(for: voiceInput, apiKey: key)
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

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                if httpResponse.statusCode == 200 {
                    guard data.count >= 12, String(data: data.prefix(4), encoding: .ascii) == "RIFF",
                          String(data: data[8..<12], encoding: .ascii) == "WAVE" else {
                        throw NSError(domain: "Typecast", code: 502, userInfo: [NSLocalizedDescriptionKey: "유효한 WAV 오디오 응답이 아님"])
                    }
                    guard let savedURL = saveToCache(data: data, for: cleanText, voiceId: resolvedVoice, alias: voiceInput) else {
                        throw NSError(domain: "Typecast", code: 500, userInfo: [NSLocalizedDescriptionKey: "오디오 캐시 저장 실패"])
                    }
                    return savedURL
                }

                throw TypecastAPIPolicy.failure(status: httpResponse.statusCode, data: data, secrets: keysToTry)
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                let failure = error as NSError
                lastFailure = failure
                failures.append("\(keyDescription(key, index: currentTryIdx)): \(failure.localizedDescription)")
                // A rate limit, timeout or invalid request is not evidence of depleted credit.
                // Do not multiply those requests across every account.
                if failure.domain != "Typecast" || !TypecastAPIPolicy.canTryNextAccount(failure.code) { break }
            }
        }

        let message = failures.joined(separator: "\n")
        await MainActor.run { self.lastStatus = "타입캐스트 실패: \(message)" }
        throw NSError(domain: lastFailure?.domain ?? "Typecast", code: lastFailure?.code ?? -1,
                      userInfo: [NSLocalizedDescriptionKey: message])
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
