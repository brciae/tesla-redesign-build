import Foundation

@main struct AutomationAPITests {
    static func main() async throws {
        func decode(_ object: [String: Any], _ provider: AutomationAPIProvider) throws -> String {
            try AutomationAPI.decodeResponse(JSONSerialization.data(withJSONObject: object), provider: provider)
        }
        let rule = "{\"schema\":1}"
        let output1 = try decode(["status": "completed", "output": [["content": [["type": "output_text", "text": rule]]]]], .openAI)
        precondition(output1 == rule)
        let output2 = try decode(["stop_reason": "end_turn", "content": [["type": "text", "text": rule]]], .anthropic)
        precondition(output2 == rule)
        let output3 = try decode(["candidates": [["finishReason": "STOP", "content": ["parts": [["thought": true, "text": "private reasoning"], ["text": rule]]]]]], .gemini)
        precondition(output3 == rule)
        let failures: [(AutomationAPIProvider, [String: Any])] = [(AutomationAPIProvider.openAI, ["status": "incomplete"]), (.anthropic, ["stop_reason": "max_tokens"]), (.gemini, ["candidates": [["finishReason": "MAX_TOKENS"]]])]
        for (provider, object) in failures {
            do { _ = try decode(object, provider); preconditionFailure("Incomplete output accepted") } catch { }
        }
        let success = try JSONSerialization.data(withJSONObject: ["candidates": [["finishReason": "STOP", "content": ["parts": [["text": rule]]]]]])
        func response(_ status: Int, _ headers: [String: String] = [:]) -> HTTPURLResponse {
            HTTPURLResponse(url: URL(string: "https://generativelanguage.googleapis.com")!, statusCode: status, httpVersion: nil, headerFields: headers)!
        }
        var calls = 0
        var waits: [TimeInterval] = []
        var notices: [Int] = []
        // First success, second generation transient failure then recovery, third success without restart.
        for statuses in [[200], [503, 503, 200], [200]] {
            var index = 0
            let result = try await AutomationAPI.complete(provider: .gemini, sleep: { waits.append($0) }, onRetry: { n, _ in notices.append(n) }) {
                let status = statuses[index]; index += 1; calls += 1
                return (success, response(status))
            }
            precondition(result == rule && index == statuses.count)
        }
        precondition(calls == 5 && notices == [1, 2] && waits.count == 2 && waits[1] > waits[0])
        // Persistent 503 stops after exactly three attempts; next independent generation still works.
        calls = 0
        do {
            _ = try await AutomationAPI.complete(provider: .gemini, sleep: { _ in }) { calls += 1; return (Data(), response(503)) }
            preconditionFailure("Persistent failure accepted")
        } catch { precondition((error as NSError).code == 503 && calls == 3) }
        let recovered = try await AutomationAPI.complete(provider: .gemini) { (success, response(200)) }
        precondition(recovered == rule)
        for status in [400, 401, 403, 404, 429] {
            calls = 0
            do {
                _ = try await AutomationAPI.complete(provider: .gemini, sleep: { _ in preconditionFailure("Non-transient retry") }) { calls += 1; return (Data(), response(status)) }
                preconditionFailure("HTTP error accepted")
            } catch { precondition((error as NSError).code == status && calls == 1) }
        }
        precondition(AutomationAPI.retryDelay(http: response(503, ["Retry-After": "12"]), data: Data(), attempt: 0) == 12)
        precondition(AutomationAPI.retryDelay(http: response(503, ["Retry-After": "120"]), data: Data(), attempt: 0) == nil)
        let retryInfo = try JSONSerialization.data(withJSONObject: ["error": ["details": [["@type": "type.googleapis.com/google.rpc.RetryInfo", "retryDelay": "8s"]]]])
        precondition(AutomationAPI.retryDelay(http: response(503), data: retryInfo, attempt: 0) == 8)
        calls = 0
        do {
            _ = try await AutomationAPI.complete(provider: .gemini, sleep: { _ in throw CancellationError() }) { calls += 1; return (Data(), response(503)) }
            preconditionFailure("Cancellation ignored")
        } catch is CancellationError { precondition(calls == 1) }
        calls = 0
        do {
            _ = try await AutomationAPI.complete(provider: .gemini, sleep: { _ in preconditionFailure("Network failure retried") }) { calls += 1; throw URLError(.timedOut) }
            preconditionFailure("Network error ignored")
        } catch { precondition(calls == 1) }
        print("PASS: provider decoding; consecutive generation; 503 recovery/exhaustion; auth/quota no retry; Retry-After/RetryInfo; cancellation; network no replay")
    }
}
