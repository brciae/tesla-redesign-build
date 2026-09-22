import Foundation
import CoreFoundation

final class FleetCommandRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum FleetCommandPolicy {
    static func proxyURL(_ text: String) throws -> URL {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: clean), parts.scheme == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, let url = parts.url else {
            throw failure("HTTPS 명령 서명 서버 주소가 필요합니다. 조회 로그인만으로는 원격 제어가 준비되지 않습니다.")
        }
        return url
    }

    static func accepted(_ data: Data) throws -> Bool {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any], let resultValue = response["result"] as? NSNumber,
              CFGetTypeID(resultValue) == CFBooleanGetTypeID() else {
            throw failure("명령 승인 응답을 확인하지 못했습니다. 차량 상태를 확인하세요. 자동 재전송하지 않습니다.")
        }
        guard resultValue.boolValue else {
            let reason = String((response["reason"] as? String ?? "차량에서 요청 거부").prefix(240))
            throw failure("차량 명령 거부: " + reason)
        }
        return true
    }

    static func failure(_ text: String) -> NSError {
        NSError(domain: "FleetCommand", code: 400, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
