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
    static func generate(provider: AutomationAPIProvider, model: String, prompt: String) async throws -> String {
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
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw failure("AI 서비스 응답을 확인할 수 없습니다.") }
        guard http.statusCode == 200 else {
            let reason = [401: "API 키 인증 실패", 403: "모델 또는 API 접근 권한 없음", 404: "모델 ID 확인 필요", 429: "사용량·요청 한도 도달" ][http.statusCode] ?? "AI 요청 실패"
            throw failure("\(reason) (HTTP \(http.statusCode)). 설정을 확인한 뒤 다시 시도해 주세요.")
        }
        var data = Data()
        for try await byte in bytes { data.append(byte); guard data.count <= 262144 else { throw failure("AI 응답이 너무 큽니다.") } }
        return try decodeResponse(data, provider: provider)
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
