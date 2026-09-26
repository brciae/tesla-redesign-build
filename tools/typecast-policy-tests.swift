import Foundation

@main
struct TypecastPolicyTests {
    static func main() {
        let legacy = "676cda78bde49be9d17f38e0"
        let id = "tc_" + legacy
        precondition(!TypecastAPIPolicy.isVoiceID(legacy))
        precondition(TypecastAPIPolicy.isVoiceID(id))
        precondition(!TypecastAPIPolicy.isVoiceID("tc_"))
        precondition(!TypecastAPIPolicy.isVoiceID("tc_bad key"))
        precondition(TypecastAPIPolicy.resolve([legacy, "아엘", "Ael"], in: ["ael": id]) == id)
        precondition(TypecastAPIPolicy.resolve([legacy], in: [legacy: id]) == id)
        precondition(TypecastAPIPolicy.resolve([legacy], in: ["other": id]) == nil)
        precondition(TypecastAPIPolicy.resolve(["아엘"], in: ["아엘": legacy]) == nil)
        for status in [400, 401, 402, 403, 404, 422, 429, 500] {
            let error = TypecastAPIPolicy.failure(status: status, data: Data("credit limit secret-key".utf8), secrets: ["secret-key"])
            precondition(error.code == status)
            precondition(!error.localizedDescription.contains("secret-key"))
            precondition(error.localizedDescription.contains("API 크레딧 부족") == (status == 402))
            precondition(TypecastAPIPolicy.canTryNextAccount(status) == false)
        }
        let blocked = TypecastAPIPolicy.failure(status: 403, data: Data(#"{"error_code":"UNUSUAL_ACTIVITY_DETECTED","message":"raw account details"}"#.utf8), secrets: [])
        precondition(blocked.localizedDescription.contains("API 이용 제한"))
        precondition(blocked.localizedDescription.contains("UNUSUAL_ACTIVITY_DETECTED"))
        precondition(!blocked.localizedDescription.contains("raw account details"))
        precondition(!blocked.localizedDescription.contains("IP당 무료 계정 제한"))
        let stage = TypecastAPIPolicy.failure(status: 403, data: Data("forbidden".utf8), secrets: [], stage: "POST /v1/text-to-speech")
        precondition(stage.localizedDescription.contains("POST /v1/text-to-speech"))
        precondition(!TypecastAPIPolicy.canTryNextAccount(blocked.code))
        print("PASS: Typecast error classification, account restriction stop, redaction and exact voice resolution")
    }
}
