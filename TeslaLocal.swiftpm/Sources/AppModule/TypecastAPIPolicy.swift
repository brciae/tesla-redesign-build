import Foundation

enum TypecastAPIPolicy {
    static func isVoiceID(_ value: String) -> Bool {
        (value.hasPrefix("tc_") || value.hasPrefix("uc_")) && value.count > 3
            && !value.contains(where: { $0.isWhitespace })
    }

    static func canTryNextAccount(_ status: Int) -> Bool {
        false
    }

    static func failure(status: Int, data: Data, secrets: [String]) -> NSError {
        if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           body["error_code"] as? String == "UNUSUAL_ACTIVITY_DETECTED" {
            return NSError(domain: "Typecast", code: status, userInfo: [
                NSLocalizedDescriptionKey: "타입캐스트 API 이용 제한(HTTP \(status)): 비정상 활동이 감지되어 요청이 거부됨. IP당 무료 계정 제한 등 API 정책 확인 필요. 추가 계정으로 재시도하지 않습니다."
            ])
        }
        let reason: String
        switch status {
        case 401: reason = "API 키 인증 실패"
        case 402: reason = "API 크레딧 부족"
        case 403: reason = "API 접근 거부: 현재 API용 키와 계정 권한 확인 필요"
        case 429: reason = "호출 제한: 잠시 후 다시 시도 필요"
        case 400, 422: reason = "음성 합성 요청 형식 오류"
        case 404: reason = "선택한 음성 또는 모델을 API에서 찾을 수 없음"
        default: reason = "타입캐스트 서버 오류"
        }
        var detail = String(data: data, encoding: .utf8) ?? ""
        for secret in secrets where !secret.isEmpty {
            detail = detail.replacingOccurrences(of: secret, with: "[REDACTED]")
        }
        detail = String(detail.prefix(400))
        return NSError(domain: "Typecast", code: status, userInfo: [
            NSLocalizedDescriptionKey: "HTTP \(status) · \(reason)\(detail.isEmpty ? "" : " · " + detail)"
        ])
    }

    static func resolve(_ candidates: [String], in catalog: [String: String]) -> String? {
        for candidate in candidates {
            let key = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            for normalized in [key, key.replacingOccurrences(of: " ", with: "")] {
                if let id = catalog[normalized], isVoiceID(id) { return id }
            }
        }
        return nil
    }
}
