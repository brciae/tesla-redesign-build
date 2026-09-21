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
    @Published var apiKey: String {
        didSet {
            let clean = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(clean, forKey: "typecastApiKey")
        }
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

    static let defaultVoiceId = "tc_60e5426de8b95f1d3000d7b5" // Popular Korean natural voice

    // Curated list of popular, high-clarity Korean voice actors on Typecast
    static let presetVoices: [(name: String, id: String, desc: String)] = [
        ("지호 (자연스러운 기본)", "tc_60e5426de8b95f1d3000d7b5", "차분하고 또렷한 표준 안내 음성"),
        ("유진 (친근한 여성)", "tc_6045d56d5f9ae03ac175cf73", "밝고 부드러운 일상 대화 톤"),
        ("민수 (신뢰감 남성)", "tc_6038fca6cfbdf354a8618e47", "전문적인 뉴스/내비게이션 톤"),
        ("소연 (발랄한 여성)", "tc_6009403d159a685cb520f9a2", "경쾌하고 활기찬 인사 톤")
    ]

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
        self.apiKey = UserDefaults.standard.string(forKey: "typecastApiKey") ?? ""
        self.selectedVoiceId = UserDefaults.standard.string(forKey: "typecastVoiceId") ?? Self.defaultVoiceId
        super.init()
        updateCacheCount()
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
        let resolvedVoice = targetVoice.isEmpty ? Self.defaultVoiceId : targetVoice

        // 1. Instant Cache Hit (0 credits, 0ms latency)
        if let cached = cachedURL(for: cleanText, voiceId: resolvedVoice) {
            return cached
        }

        // 2. Online Synthesis
        guard hasKey else {
            throw NSError(domain: "Typecast", code: 401, userInfo: [NSLocalizedDescriptionKey: "타입캐스트 API Key가 등록되지 않았습니다."])
        }

        await MainActor.run { isSynthesizing = true }
        defer { Task { @MainActor in isSynthesizing = false } }

        guard let apiURL = URL(string: "https://api.typecast.ai/v1/text-to-speech") else {
            throw NSError(domain: "Typecast", code: 500, userInfo: [NSLocalizedDescriptionKey: "API URL 생성 실패"])
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "X-API-KEY")
        request.timeoutInterval = 12.0

        let body: [String: Any] = [
            "voice_id": resolvedVoice,
            "text": cleanText,
            "model": "ssfm-v30",
            "prompt": [
                "emotion_type": "smart"
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "Typecast", code: 500, userInfo: [NSLocalizedDescriptionKey: "서버 응답 없음"])
        }

        guard httpResponse.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "Typecast", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "타입캐스트 오류 (\(httpResponse.statusCode)): \(msg)"])
        }

        guard let savedURL = saveToCache(data: data, for: cleanText, voiceId: resolvedVoice) else {
            throw NSError(domain: "Typecast", code: 500, userInfo: [NSLocalizedDescriptionKey: "오디오 캐시 저장 실패"])
        }

        return savedURL
    }

    // MARK: - Test Preview Playback

    func testSpeech(text: String = "안녕하세요! 테슬라 스마트 드라이빙을 시작합니다.", completion: (() -> Void)? = nil) {
        stop()
        testCompletion = completion
        lastStatus = "타입캐스트 음성 생성 중…"

        Task {
            do {
                let audioURL = try await synthesize(text: text)
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
