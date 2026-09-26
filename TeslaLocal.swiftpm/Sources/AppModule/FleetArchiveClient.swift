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
    @Published private(set) var connected = false
    @Published private(set) var packetCount: Int?
    @Published private(set) var lastVehicleReceivedAt: Date?
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
        connected = false; packetCount = nil; lastVehicleReceivedAt = nil
    }
    func sync(vin: String) async {
        guard !busy else { return }
        guard !vin.isEmpty else { status = "Tesla 계정에서 차량을 먼저 선택해 주세요."; return }
        guard !address.isEmpty else { status = "NAS 서버 주소와 연결 키를 저장해 주세요."; return }
        busy = true; defer { busy = false }
        connected = false; packetCount = nil; lastVehicleReceivedAt = nil
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
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                guard http.statusCode == 200 else { throw Self.responseError(http.statusCode) }
                var data = Data()
                for try await byte in bytes {
                    data.append(byte)
                    guard data.count <= 5_000_000 else { throw FleetTelemetryData.failure("NAS 응답이 너무 큽니다. 서버의 페이지 크기를 확인해 주세요.") }
                }
                guard let page = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let payloads = page["payloads"] as? [[String: Any]],
                      let next = page["next"] as? Int, let more = page["more"] as? Bool,
                      next >= cursor, (!more || next > cursor) else { throw FleetTelemetryData.failure("NAS 기록 응답 형식이 맞지 않습니다.") }
                guard address == base else { throw CancellationError() }
                connected = true
                if !payloads.isEmpty {
                    try FleetTelemetryStore.shared.ingest(JSONSerialization.data(withJSONObject: payloads), vin: vin)
                    total += payloads.count
                }
                // Persist progress only after the archive page has been saved on the phone.
                cursor = next; UserDefaults.standard.set(cursor, forKey: cursorKey)
                status = total > 0 ? "NAS 연결됨 · 새 차량 기록 \(total)건 저장" : "NAS 연결됨 · 새로 받은 차량 기록 없음"
                if !more {
                    await readStatus(base: base, key: key, vin: vin)
                    return
                }
            }
            status += " · 다음 동기화에서 나머지 기록을 이어 가져옵니다."
        } catch is CancellationError { status = "다음에 기록 가져오기를 누르면 이어집니다." }
        catch let error as URLError {
            switch error.code {
            case .timedOut, .cannotConnectToHost, .cannotFindHost: status = "NAS에 도달하지 못했습니다. 서버 실행·외부 주소·8444 포트 연결을 확인하세요."
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .secureConnectionFailed: status = "NAS HTTPS 인증서를 확인하세요. 유효한 인증서가 필요합니다."
            case .notConnectedToInternet: status = "휴대폰 인터넷 연결이 끊겼습니다."
            default: status = error.localizedDescription
            }
        }
        catch { status = error.localizedDescription }
    }

    private static func responseError(_ code: Int) -> Error {
        let text: String
        switch code {
        case 401, 403: text = "NAS에는 연결됐지만 연결 키가 거부됐습니다. NAS 전용 키를 다시 저장하세요."
        case 404: text = "이 주소에는 차량 기록 API가 없습니다. NAS 관리 주소 대신 기록 서버 주소를 입력하세요."
        case 502, 503, 504: text = "NAS 주소는 응답하지만 기록 서비스가 준비되지 않았습니다. archive·Kafka 컨테이너를 확인하세요."
        default: text = "NAS 기록 요청 실패 (HTTP \(code))."
        }
        return FleetTelemetryData.failure(text)
    }

    private func readStatus(base: String, key: String, vin: String) async {
        var url = URLComponents(string: base + "/v1/status")!
        url.queryItems = [URLQueryItem(name: "vin", value: vin)]
        var request = URLRequest(url: url.url!); request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await session.data(for: request)
            guard address == base, (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count <= 16_384, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let count = object["measurement_packets"] as? Int, count >= 0 else { return }
            packetCount = count
            if let at = object["last_vehicle_received_at"] as? Double { lastVehicleReceivedAt = Date(timeIntervalSince1970: at) }
            if count == 0 { status = "NAS 연결·키 인증 정상 · 차량에서 받은 기록 0건. 가상 키와 차량 수집 설정을 확인하세요." }
            if object["archive_ready"] as? Bool == false { status = "NAS 저장 기록은 조회되지만 수집 대기열이 중단됐습니다. Kafka·archive 상태를 확인하세요." }
        } catch { /* Older servers can still supply records without diagnostics. */ }
    }
}
