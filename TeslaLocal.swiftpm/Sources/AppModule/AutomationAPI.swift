import Foundation
import Security

/// User-selected official endpoints only. API secrets never enter the prompt or app backup.
enum AutomationAPIProvider: String, CaseIterable, Identifiable {
    case openAI = "OpenAI", anthropic = "Claude", gemini = "Gemini"
    var id: String { rawValue }
    var exampleModel: String {
        switch self { case .openAI: return "gpt-6-astra"; case .anthropic: return "claude-sonnet-4-6"; case .gemini: return "gemini-2.5-flash" }
    }
}
private final class AutomationAPIRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
enum AutomationAPI {
    static func failure(_ text: String) -> NSError { NSError(domain: "AutomationAPI", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    private static func query(_ provider: AutomationAPIProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "YL.automation.api", kSecAttrAccount as String: provider.rawValue]
    }
    static func key(_ provider: AutomationAPIProvider) -> String? {
        var q = query(provider); q[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func saveKey(_ value: String, provider: AutomationAPIProvider) throws {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 4096 else { throw failure("API 키를 입력해 주세요.") }
        let attributes: [String: Any] = [kSecValueData as String: Data(clean.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let result = SecItemUpdate(query(provider) as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            var q = query(provider); attributes.forEach { q[$0.key] = $0.value }
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw failure("API 키를 보안 저장하지 못했습니다.") }; return
        }
        guard result == errSecSuccess else { throw failure("API 키를 갱신하지 못했습니다.") }
    }
    static func removeKey(_ provider: AutomationAPIProvider) { SecItemDelete(query(provider) as CFDictionary) }
    static func generate(provider: AutomationAPIProvider, model: String, prompt: String, onRetry: ((Int, TimeInterval) async -> Void)? = nil) async throws -> String {
        guard let key = key(provider), !key.isEmpty else { throw failure("선택한 서비스의 API 키를 먼저 등록해 주세요.") }
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard model.range(of: "^[A-Za-z0-9._-]{1,100}$", options: .regularExpression) != nil else { throw failure("사용할 모델 ID를 확인해 주세요.") }
        let endpoint: String
        let body: [String: Any]
        switch provider {
        case .openAI:
            endpoint = "https://api.openai.com/v1/responses"
            body = ["model": model, "input": prompt, "max_output_tokens": 4096, "store": false]
        case .anthropic:
            endpoint = "https://api.anthropic.com/v1/messages"
            body = ["model": model, "max_tokens": 2048, "messages": [["role": "user", "content": prompt]]]
        case .gemini:
            endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
            body = ["contents": [["parts": [["text": prompt]]]], "generationConfig": ["maxOutputTokens": 4096]]
        }
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"; request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch provider {
        case .openAI: request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .gemini: request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let session = URLSession(configuration: .ephemeral, delegate: AutomationAPIRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await complete(provider: provider, onRetry: onRetry) {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw failure("AI 서비스 응답을 확인할 수 없습니다.") }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                data.append(byte)
                guard data.count <= 262144 else { throw failure("AI 응답이 너무 큽니다.") }
            }
            return (data, http)
        }
    }
    /// Retry only explicit transient HTTP responses, never ambiguous network failures or invalid drafts.
    /// Each generation owns its retry budget; no failed state carries into the next generation.
    static func complete(provider: AutomationAPIProvider,
                         sleep: (TimeInterval) async throws -> Void = { seconds in
                             try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                         },
                         onRetry: ((Int, TimeInterval) async -> Void)? = nil,
                         send: () async throws -> (Data, HTTPURLResponse)) async throws -> String {
        for attempt in 0..<3 {
            try Task.checkCancellation()
            let (data, http) = try await send()
            try Task.checkCancellation()
            if http.statusCode == 200 { return try decodeResponse(data, provider: provider) }
            if let delay = retryDelay(http: http, data: data, attempt: attempt) {
                await onRetry?(attempt + 1, delay)
                try await sleep(delay)
                continue
            }
            throw httpFailure(http.statusCode, provider: provider)
        }
        throw failure("AI 생성 재시도 한도에 도달했습니다.")
    }
    static func retryDelay(http: HTTPURLResponse, data: Data, attempt: Int, now: Date = Date()) -> TimeInterval? {
        guard [502, 503, 504].contains(http.statusCode), attempt < 2 else { return nil }
        var serverDelay: TimeInterval = 0
        if let header = http.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = Double(header), seconds.isFinite { serverDelay = max(0, seconds) }
            else {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                if let date = formatter.date(from: header) { serverDelay = max(0, date.timeIntervalSince(now)) }
            }
        }
        if let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let error = root["error"] as? [String: Any], let details = error["details"] as? [[String: Any]] {
            for detail in details where detail["@type"] as? String == "type.googleapis.com/google.rpc.RetryInfo" {
                if let raw = detail["retryDelay"] as? String, raw.hasSuffix("s"),
                   let seconds = Double(raw.dropLast()), seconds.isFinite { serverDelay = max(serverDelay, seconds) }
            }
        }
        // Do not wait indefinitely or retry earlier than the provider requested.
        guard serverDelay <= 30 else { return nil }
        return max(serverDelay, pow(2, Double(attempt + 1)) + Double.random(in: 0...0.5))
    }
    static func httpFailure(_ status: Int, provider: AutomationAPIProvider) -> NSError {
        let reason: String
        switch status {
        case 502, 503, 504:
            reason = "\(provider.rawValue) 서비스가 일시적으로 응답하지 않습니다. 잠시 뒤 다시 생성해 주세요. 앱 재시동이나 API 키 재등록은 필요하지 않습니다."
        case 401: reason = "API 키 인증에 실패했습니다. 등록한 키를 확인해 주세요."
        case 403: reason = "모델 또는 API 접근 권한이 없습니다. 서비스 설정을 확인해 주세요."
        case 404: reason = "모델을 찾을 수 없습니다. 등록한 모델 ID를 확인해 주세요."
        case 429: reason = "사용량·요청 한도에 도달했습니다. 서비스의 한도와 결제 설정을 확인한 뒤 다시 시도해 주세요."
        default: reason = "AI 요청을 처리하지 못했습니다. 잠시 뒤 다시 시도해 주세요."
        }
        // Do not echo provider bodies: they can contain prompts, identifiers or credentials.
        return NSError(domain: "AutomationAPI", code: status, userInfo: [NSLocalizedDescriptionKey: "\(reason) (HTTP \(status))"])
    }
    static func decodeResponse(_ data: Data, provider: AutomationAPIProvider) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw failure("AI 응답 형식 오류") }
        let texts: [String]
        switch provider {
        case .openAI:
            guard root["status"] as? String == "completed" else { throw failure("AI 생성이 완료되지 않았습니다. 요청을 짧게 하거나 출력 한도를 확인해 주세요.") }
            texts = (root["output"] as? [[String: Any]] ?? []).flatMap { $0["content"] as? [[String: Any]] ?? [] }.filter { $0["type"] as? String == "output_text" }.compactMap { $0["text"] as? String }
        case .anthropic:
            guard root["stop_reason"] as? String == "end_turn" else { throw failure("AI 결과가 중간에 끊겼습니다. 요청을 줄여 다시 생성해 주세요.") }
            texts = (root["content"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
        case .gemini:
            guard let candidate = (root["candidates"] as? [[String: Any]])?.first, candidate["finishReason"] as? String == "STOP" else { throw failure("AI가 완성된 규칙을 반환하지 않았습니다.") }
            texts = ((candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []).filter { $0["thought"] as? Bool != true }.compactMap { $0["text"] as? String }
        }
        let text = texts.joined(separator: "\n")
        guard !text.isEmpty else { throw failure("AI가 규칙을 반환하지 않았습니다.") }
        if let data = text.data(using: .utf8), let error = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let reason = error["error"] as? String { throw failure(String(reason.prefix(500))) }
        return text
    }
}
