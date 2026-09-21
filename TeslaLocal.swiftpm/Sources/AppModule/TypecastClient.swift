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
    // Dynamic Typecast accounts pool (each account 15,000 free credits)
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
    @Published var cacheFileCount = 0
    @Published var cacheTotalSizeMB: Double = 0.0
    @Published var voiceCatalog: [String: String] = [:]

    var apiKey: String {
        get { activeApiKey }
        set {
            if !apiKeys.isEmpty {
                apiKeys[0] = newValue
            } else {
                apiKeys = [newValue]
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

    func addAccount() {
        apiKeys.append("")
    }

    func removeAccount(at index: Int) {
        guard apiKeys.indices.contains(index), apiKeys.count > 1 else { return }
        apiKeys.remove(at: index)
        if activeKeyIndex >= apiKeys.count {
            activeKeyIndex = max(0, apiKeys.count - 1)
        }
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
        try? FileManager.default.removeItem(at: legacyDir)
    }

    override init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "typecastEnabled") != nil ? UserDefaults.standard.bool(forKey: "typecastEnabled") : true
        if let savedKeys = UserDefaults.standard.stringArray(forKey: "typecastApiKeys"), !savedKeys.isEmpty {
            self.apiKeys = savedKeys
        } else {
            let legacyKey = UserDefaults.standard.string(forKey: "typecastApiKey") ?? ""
            self.apiKeys = [legacyKey, "", "", "", ""]
        }
        self.activeKeyIndex = UserDefaults.standard.integer(forKey: "typecastActiveKeyIndex")
        self.selectedVoiceId = UserDefaults.standard.string(forKey: "typecastVoiceId") ?? Self.defaultVoiceId
        if let catalogData = UserDefaults.standard.data(forKey: "typecastVoiceCatalog"),
           let dict = try? JSONDecoder().decode([String: String].self, from: catalogData) {
            self.voiceCatalog = dict
        }
        super.init()
        migrateLegacyCacheIfNeeded()
        updateCacheCount()
        if hasKey && voiceCatalog.isEmpty {
            Task { await refreshVoiceCatalog() }
        }
    }

    // MARK: - Voice Catalog & Parsing

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
            guard let voiceId = (item["voice_id"] ?? item["actor_id"] ?? item["id"]) as? String, !voiceId.isEmpty else {
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
        }
        return result
    }

    func refreshVoiceCatalog() async {
        guard hasKey else { return }
        let endpoints = [
            "https://api.typecast.ai/v3/voices",
            "https://api.typecast.ai/v2/voices",
            "https://api.typecast.ai/v1/voices"
        ]
        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            var req = URLRequest(url: url)
            req.setValue(activeApiKey, forHTTPHeaderField: "X-API-KEY")
            req.timeoutInterval = 10.0

            if let (data, response) = try? await URLSession.shared.data(for: req),
               let http = response as? HTTPURLResponse, http.statusCode == 200 {
                let parsed = parseVoices(from: data)
                if !parsed.isEmpty {
                    await MainActor.run {
                        for (k, v) in parsed {
                            self.voiceCatalog[k] = v
                        }
                        if let encoded = try? JSONEncoder().encode(self.voiceCatalog) {
                            UserDefaults.standard.set(encoded, forKey: "typecastVoiceCatalog")
                        }
                        self.lastStatus = "보이스 카탈로그 동기화 완료 (\(self.voiceCatalog.count)개)"
                    }
                    break
                }
            }
        }
    }

    func queryVoiceRecommendation(name: String) async -> String? {
        guard hasKey, let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.typecast.ai/v1/voices/recommendations?query=\(encoded)&count=1") else { return nil }
        var req = URLRequest(url: url)
        req.setValue(activeApiKey, forHTTPHeaderField: "X-API-KEY")
        req.timeoutInterval = 8.0
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let items: [[String: Any]]
        if let arr = json as? [[String: Any]] { items = arr }
        else if let dict = json as? [String: Any], let arr = (dict["voices"] ?? dict["result"] ?? dict["data"]) as? [[String: Any]] { items = arr }
        else { items = [] }
        if let first = items.first, let voiceId = (first["voice_id"] ?? first["actor_id"] ?? first["id"]) as? String, !voiceId.isEmpty {
            return voiceId
        }
        return nil
    }

    func resolveVoiceId(for input: String) async -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Self.defaultVoiceId }

        // 1. Explicit Typecast ID format (e.g., tc_..., uc_..., or hex format)
        if trimmed.hasPrefix("tc_") || trimmed.hasPrefix("uc_") || (trimmed.count >= 20 && !trimmed.contains(" ")) {
            return trimmed
        }

        let lower = trimmed.lowercased()
        let noSpaces = lower.replacingOccurrences(of: " ", with: "")

        // 2. Check local voice catalog
        if let match = voiceCatalog[lower] ?? voiceCatalog[noSpaces] {
            return match
        }

        // 3. Dynamic lookup from recommendations endpoint
        if let rec = await queryVoiceRecommendation(name: trimmed) {
            await MainActor.run {
                self.voiceCatalog[lower] = rec
                self.voiceCatalog[noSpaces] = rec
                if let encoded = try? JSONEncoder().encode(self.voiceCatalog) {
                    UserDefaults.standard.set(encoded, forKey: "typecastVoiceCatalog")
                }
            }
            return rec
        }

        // 4. Fallback: refresh whole catalog from /v3/voices
        if hasKey {
            await refreshVoiceCatalog()
            if let match = voiceCatalog[lower] ?? voiceCatalog[noSpaces] {
                return match
            }
            // Partial match
            if let partial = voiceCatalog.first(where: { $0.key.contains(noSpaces) || noSpaces.contains($0.key) })?.value {
                return partial
            }
            // First valid tc_ voice
            if let first = voiceCatalog.values.first(where: { $0.hasPrefix("tc_") || $0.count >= 20 }) {
                return first
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
        let resolvedVoice = await resolveVoiceId(for: targetVoice.isEmpty ? Self.defaultVoiceId : targetVoice)

        // 1. Instant Cache Hit (0 credits, 0ms latency)
        if let cached = cachedURL(for: cleanText, voiceId: targetVoice) ?? cachedURL(for: cleanText, voiceId: resolvedVoice) {
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
                    guard let savedURL = saveToCache(data: data, for: cleanText, voiceId: resolvedVoice, alias: targetVoice) else {
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

        await MainActor.run {
            self.lastStatus = "타입캐스트 실패: \(lastErrorMsg)"
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
