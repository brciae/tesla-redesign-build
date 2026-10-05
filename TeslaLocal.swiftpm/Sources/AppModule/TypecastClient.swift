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
    @Published var showVoicePicker = false
    /// v1.42: every voice the account can use (all genders/ages), from GET /v3/voices; cached for offline browsing.
    @Published var remoteVoices: [TypecastCharacter] = TypecastClient.loadRemoteVoices()
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
            let catalog = try await fetchVoiceCatalog(apiKey: key, force: true)
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

    // Validated metadata is scoped to the selected key and expires after 10 minutes.
    private var catalogKeyFingerprint = ""
    private var catalogFetchedAt = Date.distantPast
    private var catalogRequest: Task<[String: String], Error>?
    private var catalogRequestKey = ""
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

    /// v1.34: each voice keeps its own sub-folder so one character's bad takes can be deleted alone.
    /// Files from before v1.34 sit in the root ("미분류") and move into their voice folder on first use.
    private func voiceDirectory(_ voiceId: String) -> URL {
        let safe = voiceId.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        let dir = cacheDirectory.appendingPathComponent("v_" + String(safe), isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        return dir
    }
    struct VoiceCacheEntry: Identifiable, Hashable { let id: String; let name: String; let count: Int; let megabytes: Double }
    @Published var cacheByVoice: [VoiceCacheEntry] = []
    static let unsortedCacheID = "__unsorted"
    func voiceName(_ id: String) -> String {
        if id == Self.unsortedCacheID { return "미분류 (v1.34 이전 저장분)" }
        // v1.49: name from the saved voice list first — the live catalog is empty until a network sync.
        if let v = remoteVoices.first(where: { $0.id == id }) { return v.nameKo }
        if let c = TypecastCatalog.find(id) { return c.nameKo }
        if let name = voiceCatalog.first(where: { $0.value == id && !$0.key.hasPrefix("tc_") && !$0.key.hasPrefix("uc_") })?.key { return name }
        return "이름 확인 중 (\(id.prefix(10)))"
    }
    /// v1.46: one cached recording with the sentence it says (recorded from 1.46 on; older files have no text).
    struct CachedPhrase: Identifiable, Hashable { let id: URL; let text: String; let group: String; let kilobytes: Int; let date: Date }
    static func phraseGroup(_ t: String) -> String {
        if t.isEmpty { return "문구 기록 없음 (1.46 이전 저장분)" }
        let has = { (k: [String]) in k.contains { t.contains($0) } }
        if has(["단속", "제한", "과속", "어린이", "보호구역", "주의", "사고", "버스 전용", "위험", "낙석", "안개"]) { return "안전·단속 안내" }
        if has(["미터", "킬로미터", "회전", "좌회전", "우회전", "유턴", "직진", "방면", "차로", "출구", "진출", "합류", "도착", "경로", "목적지"]) { return "길안내" }
        if has(["충전", "배터리", "잔량", "퍼센트"]) { return "충전·배터리" }
        if has(["문", "트렁크", "프렁크", "창문", "잠금", "잠겼", "공조", "온도", "시트", "에어컨", "히터"]) { return "차량 제어·상태" }
        if has(["안녕", "반가", "출발", "다녀", "어서", "좋은"]) { return "인사·브리핑" }
        return "기타"
    }
    func cachedPhrases(voice id: String) -> [CachedPhrase] {
        let dir = id == Self.unsortedCacheID ? cacheDirectory : cacheDirectory.appendingPathComponent(voiceDirectory(id).lastPathComponent, isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "wav" }.map { f in
            let text = (try? String(contentsOf: f.deletingPathExtension().appendingPathExtension("txt"), encoding: .utf8)) ?? ""
            let v = try? f.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return CachedPhrase(id: f, text: text, group: Self.phraseGroup(text), kilobytes: (v?.fileSize ?? 0) / 1024, date: v?.contentModificationDate ?? .distantPast)
        }.sorted { $0.date > $1.date }
    }
    func deleteCached(_ items: [CachedPhrase]) {
        for i in items {
            try? FileManager.default.removeItem(at: i.id)
            try? FileManager.default.removeItem(at: i.id.deletingPathExtension().appendingPathExtension("txt"))
        }
        updateCacheCount()
        lastStatus = "음성 캐시 \(items.count)개를 삭제했습니다."
    }
    func clearCache(voice id: String) {
        if id == Self.unsortedCacheID {
            let files = (try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
            for f in files where f.pathExtension == "wav" || f.pathExtension == "txt" { try? FileManager.default.removeItem(at: f) }
        } else {
            try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent(voiceDirectory(id).lastPathComponent, isDirectory: true))
        }
        updateCacheCount()
        lastStatus = "\(voiceName(id)) 음성 캐시를 삭제했습니다."
    }

    /// One-time purge of short clips synthesised with "smart" emotion (some came back whispered).
    /// Short cues are tiny WAVs; long reports are kept so they need no re-synthesis.
    private func purgeWhisperedShortClipsOnce() {
        let flag = "typecastToneV2Purged"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        let dir = cacheDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        for url in files where url.pathExtension == "wav" {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 260_000 { try? FileManager.default.removeItem(at: url) }
        }
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
        purgeWhisperedShortClipsOnce()
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

    @MainActor
    private func fetchVoiceCatalog(apiKey: String, force: Bool = false) async throws -> [String: String] {
        let fingerprint = SHA256.hash(data: Data(apiKey.utf8)).map { String(format: "%02x", $0) }.joined()
        if !force, catalogKeyFingerprint == fingerprint, Date().timeIntervalSince(catalogFetchedAt) < 600, !voiceCatalog.isEmpty { return voiceCatalog }
        if catalogRequestKey == fingerprint, let pending = catalogRequest { return try await pending.value }
        let task = Task { try await self.requestVoiceCatalog(apiKey: apiKey) }
        catalogRequest = task; catalogRequestKey = fingerprint
        defer { if catalogRequestKey == fingerprint { catalogRequest = nil; catalogRequestKey = "" } }
        let catalog = try await task.value
        voiceCatalog = catalog; catalogKeyFingerprint = fingerprint; catalogFetchedAt = Date()
        return catalog
    }

    private func requestVoiceCatalog(apiKey: String) async throws -> [String: String] {
        // v1.46: no model filter — list every voice the account can use; each voice is synthesised with its best model.
        let url = URL(string: "https://api.typecast.ai/v3/voices")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            throw TypecastAPIPolicy.failure(status: http.statusCode, data: data, secrets: [apiKey], stage: "GET /v3/voices")
        }
        let catalog = parseVoices(from: data)
        let voices = Self.parseVoiceMetadata(data)
        if !voices.isEmpty {
            UserDefaults.standard.set(data, forKey: "typecast.voiceListRaw")
            // only publish real changes — reassigning the same list made open pickers jump back to the top
            await MainActor.run { if voices.map(\.id) != self.remoteVoices.map(\.id) { self.remoteVoices = voices; self.updateCacheCount() } }
        }
        guard !catalog.isEmpty else {
            throw NSError(domain: "Typecast", code: 502, userInfo: [NSLocalizedDescriptionKey: "HTTP 200이지만 지원 보이스 목록을 해석할 수 없음"])
        }
        return catalog
    }

    static func bestModel(_ models: [String]) -> String {
        for m in ["ssfm-v30", "ssfm-v31", "ssfm-v21"] where models.contains(m) { return m }
        return models.first ?? "ssfm-v30"
    }
    /// Model to synthesise a resolved voice id with (v30 keeps the established tone; others use what they support).
    func model(forVoice id: String) -> String {
        remoteVoices.first { $0.id == id }?.model ?? "ssfm-v30"
    }
    /// v1.46: plays Typecast's own sample clip — no credits spent, works for every listed voice.
    func playPreview(_ urlString: String, completion: (() -> Void)? = nil) {
        stop()
        guard let url = URL(string: urlString) else { completion?(); return }
        testCompletion = completion
        previewTask = Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                try Task.checkCancellation()
                await MainActor.run {
                    do {
                        try VoiceAudioRouting.activate()
                        let p = try AVAudioPlayer(data: data)
                        p.delegate = self; p.prepareToPlay()
                        guard p.play() else { throw NSError(domain: "TypecastPreview", code: 1) }
                        self.player = p
                    } catch { VoiceAudioRouting.release(); self.testCompletion?(); self.testCompletion = nil }
                }
            } catch {
                await MainActor.run { self.testCompletion?(); self.testCompletion = nil }
            }
        }
    }
    static func loadRemoteVoices() -> [TypecastCharacter] {
        guard let data = UserDefaults.standard.data(forKey: "typecast.voiceListRaw") else { return [] }
        return parseVoiceMetadata(data)
    }
    static func parseVoiceMetadata(_ data: Data) -> [TypecastCharacter] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let list = (json as? [[String: Any]]) ?? ((json as? [String: Any]).flatMap { ($0["result"] ?? $0["voices"] ?? $0["data"]) as? [[String: Any]] }) ?? []
        func text(_ v: Any?) -> String {
            if let s = v as? String { return s }
            if let d = v as? [String: Any] { return (d["kor"] ?? d["ko"] ?? d["eng"] ?? d["en"] ?? d.values.first) as? String ?? "" }
            return ""
        }
        let genders = ["female": "여성", "male": "남성"]
        let ages = ["child": "어린이", "teenager": "청소년", "teen": "청소년", "young_adult": "청년", "middle_age": "중년", "middle_aged": "중년", "elder": "노년", "senior": "노년", "old": "노년"]
        return list.compactMap { item in
            guard let id = (item["voice_id"] ?? item["actor_id"] ?? item["id"]) as? String, TypecastAPIPolicy.isVoiceID(id) else { return nil }
            let name = text(item["voice_name"] ?? item["name"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let g = text(item["gender"]).lowercased(), a = text(item["age"]).lowercased()
            let uses = (item["use_cases"] as? [String]) ?? (item["use_case"] as? [String]) ?? []
            let models = ((item["models"] as? [Any]) ?? []).compactMap { m -> String? in
                if let s = m as? String { return s }
                return (m as? [String: Any])?["version"] as? String ?? (m as? [String: Any])?["model"] as? String
            }
            let gender = genders[g] ?? (g.isEmpty ? "미분류" : g), age = ages[a] ?? (a.isEmpty ? "미분류" : a)
            return TypecastCharacter(id: id, nameKo: name, nameEn: name, tone: "", mood: "", category: uses.joined(separator: ", "),
                                     desc: ([gender, age] + uses.prefix(2)).joined(separator: " · "), gender: gender, age: age,
                                     model: bestModel(models), previewURL: item["preview_url"] as? String ?? "")
        }
    }

    func refreshVoiceCatalog(quiet: Bool = false) async {
        guard hasKey else { return }
        do {
            _ = try await fetchVoiceCatalog(apiKey: activeApiKey, force: remoteVoices.isEmpty)
            if !quiet { await MainActor.run { self.lastStatus = "API 보이스 목록 동기화 완료 (\(self.remoteVoices.count)개)" } }
        } catch {
            if !quiet { await MainActor.run { self.lastStatus = error.localizedDescription } }
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
                "선택한 음성을 현재 계정의 API 음성 목록에서 찾을 수 없음. API 지원 음성 확인 필요"])
        }
        return id
    }

    var hasKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Cache Management

    static func presetTone(_ text: String) -> Bool { text.count <= 40 }
    /// Appends 0.6 s of silence so car/Bluetooth output latency never clips the last syllable.
    static func paddedTail(_ wav: Data, seconds: Double = 0.6) -> Data {
        var d = wav
        func u32(_ o: Int) -> UInt32 { d[d.startIndex + o ..< d.startIndex + o + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } }
        func put(_ v: UInt32, _ o: Int) { withUnsafeBytes(of: v.littleEndian) { d.replaceSubrange(d.startIndex + o ..< d.startIndex + o + 4, with: $0) } }
        var o = 12, byteRate: UInt32 = 0, blockAlign = 0
        while o + 8 <= d.count {
            let id = String(data: d[d.startIndex + o ..< d.startIndex + o + 4], encoding: .ascii) ?? ""
            let size = Int(u32(o + 4))
            if id == "fmt " { byteRate = u32(o + 16); blockAlign = Int(d[d.startIndex + o + 20]) | Int(d[d.startIndex + o + 21]) << 8 }
            if id == "data" {
                guard byteRate > 0, o + 8 + size == d.count else { return wav }
                var extra = Int(Double(byteRate) * seconds)
                if blockAlign > 0 { extra -= extra % blockAlign }
                d.append(Data(count: extra))
                put(UInt32(size + extra), o + 4)
                put(UInt32(d.count - 8), 4)
                return d
            }
            o += 8 + size + (size & 1)
        }
        return wav
    }

    private func cacheKey(for text: String, voiceId: String) -> String {
        let input = "\(voiceId)_\(text)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func cachedURL(for text: String, voiceId: String) -> URL? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = voiceId.lowercased()
        let noSpaces = lower.replacingOccurrences(of: " ", with: "")
        var ids = [voiceId]
        if let mapped = voiceCatalog[lower] ?? voiceCatalog[noSpaces], mapped != voiceId { ids.append(mapped) }
        for id in ids {
            let key = cacheKey(for: clean, voiceId: id)
            let inVoice = voiceDirectory(id).appendingPathComponent("\(key).wav")
            if isFileValid(inVoice) { return inVoice }
            // Pre-v1.34 file in the shared root: file it under this voice now.
            let legacy = cacheDirectory.appendingPathComponent("\(key).wav")
            if isFileValid(legacy) {
                if (try? FileManager.default.moveItem(at: legacy, to: inVoice)) != nil { updateCacheCount(); return inVoice }
                return legacy
            }
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
        let fileURL = voiceDirectory(voiceId).appendingPathComponent("\(key).wav")
        do {
            try data.write(to: fileURL, options: .atomic)
            try? Data(clean.utf8).write(to: fileURL.deletingPathExtension().appendingPathExtension("txt"))
            if let alias, !alias.isEmpty, alias != voiceId {
                let aliasKey = cacheKey(for: clean, voiceId: alias)
                let aliasURL = voiceDirectory(voiceId).appendingPathComponent("\(aliasKey).wav")
                try? data.write(to: aliasURL, options: .atomic)
                try? Data(clean.utf8).write(to: aliasURL.deletingPathExtension().appendingPathExtension("txt"))
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
        let fm = FileManager.default
        func scan(_ dir: URL) -> (Int, UInt64) {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            var n = 0, bytes: UInt64 = 0
            for f in files where f.pathExtension == "wav" {
                n += 1; bytes += UInt64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            return (n, bytes)
        }
        var entries: [VoiceCacheEntry] = []
        var total = 0, totalBytes: UInt64 = 0
        let root = scan(cacheDirectory)
        if root.0 > 0 { entries.append(VoiceCacheEntry(id: Self.unsortedCacheID, name: voiceName(Self.unsortedCacheID), count: root.0, megabytes: Double(root.1) / 1_048_576)) }
        total += root.0; totalBytes += root.1
        let dirs = (try? fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for d in dirs where d.lastPathComponent.hasPrefix("v_") {
            let r = scan(d)
            guard r.0 > 0 else { continue }
            let id = String(d.lastPathComponent.dropFirst(2))
            entries.append(VoiceCacheEntry(id: id, name: voiceName(id), count: r.0, megabytes: Double(r.1) / 1_048_576))
            total += r.0; totalBytes += r.1
        }
        cacheFileCount = total
        cacheTotalSizeMB = Double(totalBytes) / 1_048_576
        cacheByVoice = entries.sorted { $0.name < $1.name }
    }

    // MARK: - API Speech Synthesis

    @MainActor private var synthesisFlight: (id: UUID, task: Task<URL, Error>, preparation: Bool, text: String, voice: String)?
    private var previewTask: Task<Void, Never>?

    private func pauseKey(_ key: String) -> String {
        "typecastPaused." + SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    var synthesisPaused: Bool { UserDefaults.standard.bool(forKey: pauseKey(activeApiKey)) }

    func allowSynthesisAfterRestrictionResolved() {
        UserDefaults.standard.removeObject(forKey: pauseKey(activeApiKey))
        lastStatus = "재시도 허용됨 · 미리듣기를 누르면 합성을 요청합니다."
    }

    /// One network synthesis at a time. Playback cancellation never restarts an accepted request.
    @MainActor
    func synthesize(text: String, voiceId: String? = nil, validUntil: Date? = nil, preparation: Bool = false) async throws -> URL {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedVoice = (voiceId ?? selectedVoiceId).trimmingCharacters(in: .whitespacesAndNewlines)
        let voice = requestedVoice.isEmpty ? Self.defaultVoiceId : requestedVoice
        let key = activeApiKey
        while true {
            try Task.checkCancellation()
            if let validUntil, Date() >= validUntil { throw CancellationError() }
            if let cached = cachedURL(for: clean, voiceId: voice) { return cached }
            if let flight = synthesisFlight {
                if TypecastAPIPolicy.shouldPreemptPreparation(incomingPreparation: preparation, runningPreparation: flight.preparation, samePhrase: flight.text == clean && flight.voice == voice) {
                    flight.task.cancel()
                }
                _ = await flight.task.result
                if synthesisFlight?.id == flight.id { synthesisFlight = nil }
                continue
            }
            guard key == activeApiKey else { throw CancellationError() }
            if UserDefaults.standard.bool(forKey: pauseKey(key)) {
                throw NSError(domain: "Typecast", code: 403, userInfo: [NSLocalizedDescriptionKey:
                    "이 키는 403 응답 이후 추가 합성을 중지했습니다. 저장된 음성은 계속 사용합니다. 이용 제한이 해제된 뒤 설정에서 재시도를 허용하세요."])
            }
            let id = UUID()
            let task = Task { @MainActor in
                do { return try await self.performSynthesis(text: clean, voiceId: voice) }
                catch {
                    if (error as NSError).code == 403 {
                        UserDefaults.standard.set(true, forKey: self.pauseKey(key))
                    }
                    throw error
                }
            }
            synthesisFlight = (id, task, preparation, clean, voice)
            let result = await task.result
            if synthesisFlight?.id == id { synthesisFlight = nil }
            try Task.checkCancellation()
            return try result.get()
        }
    }

    /// Synthesizes speech via Typecast API or returns immediately from local disk cache.
    @MainActor
    private func performSynthesis(text: String, voiceId: String? = nil) async throws -> URL {
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
                try Task.checkCancellation()
                var request = URLRequest(url: apiURL)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(key, forHTTPHeaderField: "X-API-KEY")
                request.timeoutInterval = 60.0 // Full reports need more synthesis time; navigation retains its playback deadline.

                let voiceModel = self.model(forVoice: resolvedVoice)
                var body: [String: Any] = [
                    "voice_id": resolvedVoice,
                    "text": cleanText,
                    "model": voiceModel,
                    "output": [
                        "audio_format": "wav",
                        "volume": 100
                    ]
                ]
                // "smart" guesses emotion from context; terse cues such as "계속 직진하세요." came back whispered.
                if voiceModel != "ssfm-v21" {
                    body["prompt"] = Self.presetTone(cleanText)
                        ? ["emotion_type": "preset", "emotion_preset": "normal", "emotion_intensity": 1.0] as [String: Any]
                        : ["emotion_type": "smart"] as [String: Any]
                }
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

                throw TypecastAPIPolicy.failure(status: httpResponse.statusCode, data: data, secrets: keysToTry, stage: "POST /v1/text-to-speech · model=\(voiceModel) · voice=\(resolvedVoice)")
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

    func testSpeech(text: String = "음성 연결 확인. 300미터 앞에서 우회전하세요.", voiceId: String? = nil, completion: (() -> Void)? = nil) {
        stop()
        testCompletion = completion
        lastStatus = "타입캐스트 음성 생성 중…"

        previewTask = Task {
            do {
                let audioURL = try await synthesize(text: text, voiceId: voiceId)
                await MainActor.run {
                    do {
                        try VoiceAudioRouting.activate()

                        let p = try AVAudioPlayer(contentsOf: audioURL)
                        p.delegate = self
                        p.prepareToPlay()
                        guard p.play() else { throw NSError(domain: "TypecastPlayback", code: 1, userInfo: [NSLocalizedDescriptionKey: "오디오 재생을 시작하지 못했습니다."]) }
                        self.player = p
                        self.lastStatus = "타입캐스트 음성 재생 중"
                    } catch {
                        VoiceAudioRouting.release()
                        self.lastStatus = "오디오 재생 실패: \(error.localizedDescription)"
                        completion?()
                    }
                }
            } catch {
                if error is CancellationError { return }
                await MainActor.run {
                    self.lastStatus = "합성 실패: \(error.localizedDescription)"
                    completion?()
                }
            }
        }
    }

    func stop() {
        previewTask?.cancel()
        previewTask = nil
        player?.stop()
        player = nil
        VoiceAudioRouting.release()
        testCompletion?()
        testCompletion = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === self.player else { return }
        lastStatus = flag ? "재생 완료" : "오디오 재생 중단"
        self.player = nil
        VoiceAudioRouting.release()
        testCompletion?()
        testCompletion = nil
    }
}
