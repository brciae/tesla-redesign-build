import Foundation

enum FleetAuthPolicy {
    static let tokenURL = URL(string: "https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token")!
    static let asiaPacificURL = "https://fleet-api.prd.na.vn.cloud.tesla.com"

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
