import Foundation
import Security
import CryptoKit

private final class ArchiveRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never forward the private archive token to a redirect.
    }
}

@MainActor final class FleetArchiveClient: ObservableObject {
    static let shared = FleetArchiveClient()
    @Published private(set) var busy = false
    @Published private(set) var status = "NAS 연결 주소를 등록하면 저장된 차량 기록을 가져옵니다."
    var address: String { UserDefaults.standard.string(forKey: "fleet.archive.address") ?? "" }
    private let redirectGuard = ArchiveRedirectGuard()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config, delegate: redirectGuard, delegateQueue: nil)
    }()
    private func keyQuery(_ address: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "YLCompanion.FleetArchive",
         kSecAttrAccount as String: address]
    }
    private func token(_ address: String) throws -> String {
        var query = keyQuery(address); query[kSecReturnData as String] = true
        var item: CFTypeRef?
        let result = SecItemCopyMatching(query as CFDictionary, &item)
        guard result == errSecSuccess, let data = item as? Data, let text = String(data: data, encoding: .utf8) else {
            throw FleetTelemetryData.failure("NAS 연결 키를 등록해 주세요.")
        }
        return text
    }
    func configure(address input: String, token inputToken: String) throws {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URLComponents(string: clean), url.scheme == "https", url.host?.isEmpty == false,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty else { throw FleetTelemetryData.failure("NAS 서버의 HTTPS 주소만 입력해 주세요. 예: https://차량서버주소:포트") }
        let key = inputToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            guard key.count >= 32, key.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else {
                throw FleetTelemetryData.failure("서버에서 발급한 연결 키를 그대로 입력해 주세요.")
            }
            let values: [String: Any] = [kSecValueData as String: Data(key.utf8),
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
            let result = SecItemUpdate(keyQuery(clean) as CFDictionary, values as CFDictionary)
            if result == errSecItemNotFound {
                var item = keyQuery(clean); values.forEach { item[$0.key] = $0.value }
                guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw FleetTelemetryData.failure("NAS 연결 키를 보안 저장하지 못했습니다.") }
            } else if result != errSecSuccess { throw FleetTelemetryData.failure("NAS 연결 키를 갱신하지 못했습니다.") }
        } else { _ = try token(clean) }
        UserDefaults.standard.set(clean, forKey: "fleet.archive.address")
        status = "NAS 연결 설정 저장됨"
    }
    func sync(vin: String) async {
        guard !busy, !vin.isEmpty, !address.isEmpty else { return }
        busy = true; defer { busy = false }
        do {
            let base = address, key = try token(base)
            let scope = SHA256.hash(data: Data((base + "|" + vin).utf8)).map { String(format: "%02x", $0) }.joined()
            let cursorKey = "fleet.archive.cursor." + scope
            var cursor = UserDefaults.standard.integer(forKey: cursorKey), total = 0
            for _ in 0..<20 {
                try Task.checkCancellation()
                var url = URLComponents(string: base + "/v1/telemetry")!
                url.queryItems = [URLQueryItem(name: "vin", value: vin), URLQueryItem(name: "after", value: String(cursor))]
                var request = URLRequest(url: url.url!); request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw FleetTelemetryData.failure("NAS 기록을 가져오지 못했습니다. 서버 주소와 연결 키를 확인해 주세요.")
                }
                var data = Data()
                for try await byte in bytes {
                    data.append(byte)
                    guard data.count <= 5_000_000 else { throw FleetTelemetryData.failure("NAS 응답이 너무 큽니다. 서버의 페이지 크기를 확인해 주세요.") }
                }
                guard let page = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let payloads = page["payloads"] as? [[String: Any]],
                      let next = page["next"] as? Int, let more = page["more"] as? Bool,
                      next >= cursor, (!more || next > cursor) else { throw FleetTelemetryData.failure("NAS 기록 응답 형식이 맞지 않습니다.") }
                if !payloads.isEmpty {
                    try FleetTelemetryStore.shared.ingest(JSONSerialization.data(withJSONObject: payloads), vin: vin)
                    total += payloads.count
                }
                // Persist progress only after the archive page has been saved on the phone.
                cursor = next; UserDefaults.standard.set(cursor, forKey: cursorKey)
                status = "NAS 기록 \(total)건 동기화"
                if !more { return }
            }
            status += " · 다음 동기화에서 나머지 기록을 이어 가져옵니다."
        } catch is CancellationError { status = "다음에 기록 가져오기를 누르면 이어집니다." }
        catch { status = error.localizedDescription }
    }
}
