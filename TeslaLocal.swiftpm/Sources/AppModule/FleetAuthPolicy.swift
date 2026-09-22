import Foundation

enum FleetAuthPolicy {
    static let tokenURL = URL(string: "https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token")!
    static let asiaPacificURL = "https://fleet-api.prd.na.vn.cloud.tesla.com"

    static func preservesRefreshToken(storedAccess: String?, incomingAccess: String) -> Bool {
        let clean = incomingAccess.trimmingCharacters(in: .whitespacesAndNewlines)
        return !clean.isEmpty && storedAccess == clean
    }

    static func apiFailure(status: Int, data: Data, stage: String, secrets: [String] = []) -> NSError {
        let help: String
        switch status {
        case 401: help = "인증 만료 또는 권한 취소 · 새 로그인 필요"
        case 402: help = "Fleet API 결제 설정 확인 필요"
        case 403: help = "앱 권한 또는 차량 명령 키 등록 확인 필요"
        case 408: help = "차량 응답 없음 · 절전 또는 통신 상태 확인 필요"
        case 412: help = "요청 사전 조건 미충족 · 현재 리전의 개발자 앱(Partner Account) 등록 확인 필요"
        case 421: help = "계정 리전과 선택 서버 불일치"
        case 429: help = "호출 제한 · 잠시 후 다시 시도 필요"
        default: help = "Fleet 서버 응답 확인 필요"
        }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        var detail = ["error", "error_description"].compactMap { body[$0] as? String }.filter { !$0.isEmpty }.joined(separator: " · ")
        for secret in secrets where !secret.isEmpty { detail = detail.replacingOccurrences(of: secret, with: "[비공개]") }
        for pattern in [#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, #"(?i)[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}"#, #"\b[A-HJ-NPR-Z0-9]{17}\b"#] {
            detail = detail.replacingOccurrences(of: pattern, with: "[비공개]", options: .regularExpression)
        }
        detail = String(detail.prefix(400))
        return NSError(domain: "TeslaFleet", code: status, userInfo: [NSLocalizedDescriptionKey: "\(stage) HTTP \(status): \(help)\(detail.isEmpty ? "" : "\n" + detail)"])
    }

    // Used only to schedule refresh. Server validation remains authoritative.
    static func needsRefresh(_ token: String, now: Date = Date()) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return false }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expiry = claims["exp"] as? Double else { return false }
        return expiry <= now.timeIntervalSince1970 + 60
    }

    static func formBody(_ values: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return Data(values.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
    }

    static func callbackCode(_ text: String, redirect: String, state: String) throws -> String {
        guard !state.isEmpty,
              let url = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let expected = URLComponents(string: redirect),
              url.scheme == expected.scheme, url.host == expected.host,
              url.port == expected.port,
              (url.path == expected.path || url.path == expected.path + "/"),
              url.user == nil, url.password == nil, url.fragment == nil else {
            throw failure("이번 로그인 완료 후 주소창의 전체 리다이렉트 URL을 붙여넣어 주세요. 코드만 입력하거나 이전 주소를 재사용할 수 없습니다.")
        }
        let items = url.queryItems ?? []
        guard items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == state else {
            throw failure("로그인 세션이 일치하지 않습니다. 1단계에서 새로 로그인해 주세요.")
        }
        guard !items.contains(where: { $0.name == "error" }),
              items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw failure("로그인이 취소됐거나 인증 코드가 없습니다. 새로 로그인해 주세요.")
        }
        return code
    }

    static func failure(_ message: String) -> NSError {
        NSError(domain: "TeslaOAuth", code: 400, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
