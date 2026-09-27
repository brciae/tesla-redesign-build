import Foundation

@main struct AutomationAPITests {
    static func main() throws {
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
        print("PASS: three API response formats, incomplete rejection, reasoning exclusion")
    }
}
