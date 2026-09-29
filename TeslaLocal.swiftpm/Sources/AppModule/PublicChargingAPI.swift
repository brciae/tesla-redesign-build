import Foundation
import Security

private final class PublicChargingRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum PublicChargingKey {
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "YL.public.charging", kSecAttrAccount as String: "data.go.kr"] }
    static func read() -> String? {
        var q = query; q[kSecReturnData as String] = true
        var value: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ value: String) throws {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 512, !clean.contains(where: \.isWhitespace) else { throw PublicChargingData.failure("인증키를 확인하세요.") }
        let attributes: [String: Any] = [kSecValueData as String: Data((clean.removingPercentEncoding ?? clean).utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; attributes.forEach { q[$0.key] = $0.value }
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw PublicChargingData.failure("인증키를 보안 저장하지 못했습니다.") }
        } else if status != errSecSuccess { throw PublicChargingData.failure("인증키를 보안 저장하지 못했습니다.") }
    }
}

actor PublicChargingAPI {
    static let shared = PublicChargingAPI()
    private struct Cache: Codable { var region: String; var catalogAt: Date; var fetchedAt: Date; var rows: [PublicCharger] }
    private var caches: [String: Cache] = [:]
    private var cacheLoaded = false
    private var loading = false
    private let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("public-charging-regions.json")
    /// Several sigungu at once ("41460,41130"); each keeps its own cache. Rows are merged by charger ID.
    func sites(regions: String) async throws -> [NearbyChargingSite] {
        let codes = regions.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        guard !codes.isEmpty else { throw PublicChargingData.failure("조회할 시·군·구를 선택하세요.") }
        var merged: [String: NearbyChargingSite] = [:]
        var firstError: Error?
        for code in codes.prefix(8) {
            do { for site in try await sites(region: code) { merged[site.id] = site } }
            catch is CancellationError { throw CancellationError() }
            catch { firstError = firstError ?? error }
        }
        if merged.isEmpty, let firstError { throw firstError }
        return Array(merged.values)
    }
    func sites(region: String) async throws -> [NearbyChargingSite] {
        guard region.range(of: "^[0-9]{5}$", options: .regularExpression) != nil else { throw PublicChargingData.failure("조회할 시·군·구를 선택하세요.") }
        guard let key = PublicChargingKey.read() else { throw PublicChargingData.failure("공공데이터 인증키를 등록하세요.") }
        if !cacheLoaded, let data = try? Data(contentsOf: cacheURL) { caches = (try? JSONDecoder().decode([String: Cache].self, from: data)) ?? [:] }
        cacheLoaded = true
        let cache = caches[region]
        let now = Date()
        if let cache, cache.region == region, now.timeIntervalSince(cache.fetchedAt) < 60 { return PublicChargingData.sites(cache.rows, fetchedAt: cache.fetchedAt) }
        guard !loading else { throw PublicChargingData.failure("충전소 조회 중입니다. 잠시 후 다시 확인하세요.") }
        loading = true; defer { loading = false }
        var delta = cache.map { $0.region == region && now.timeIntervalSince($0.fetchedAt) < 540 && now.timeIntervalSince($0.catalogAt) < 86400 } ?? false
        var updates = try await pages(region: region, key: key, delta: delta)
        if delta, let cache {
            let existing = Set(cache.rows.map(\.id))
            if updates.contains(where: { !existing.contains($0.id) }) {
                delta = false; updates = try await pages(region: region, key: key, delta: false)
            }
        }
        try Task.checkCancellation()
        let rows = PublicChargingData.merge(delta ? cache?.rows ?? [] : [], updates)
        let next = Cache(region: region, catalogAt: delta ? cache!.catalogAt : now, fetchedAt: now, rows: rows)
        caches[region] = next
        if let data = try? JSONEncoder().encode(caches) { try? data.write(to: cacheURL, options: .atomic) }
        return PublicChargingData.sites(rows, fetchedAt: now)
    }
    private func pages(region: String, key: String, delta: Bool) async throws -> [PublicCharger] {
        let session = URLSession(configuration: .ephemeral, delegate: PublicChargingRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var all: [PublicCharger] = []
        for page in 1...10 {
            try Task.checkCancellation()
            var url = URLComponents(string: "https://apis.data.go.kr/B552584/EvCharger/" + (delta ? "getChargerStatus" : "getChargerInfo"))!
            url.queryItems = [URLQueryItem(name: "serviceKey", value: key), URLQueryItem(name: "dataType", value: "JSON"),
                URLQueryItem(name: "pageNo", value: String(page)), URLQueryItem(name: "numOfRows", value: "9999"),
                URLQueryItem(name: "zcode", value: String(region.prefix(2))), URLQueryItem(name: "zscode", value: region)]
            if delta { url.queryItems?.append(URLQueryItem(name: "period", value: "10")) }
            var request = URLRequest(url: url.url!); request.timeoutInterval = 30
            let data: Data
            do {
                let response: URLResponse
                (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw PublicChargingData.failure("공공 충전소 서버 응답 오류") }
            } catch is CancellationError { throw CancellationError() }
            catch { throw PublicChargingData.failure("공공 충전소에 연결하지 못했습니다. 네트워크와 인증키를 확인하세요.") }
            let decoded = try PublicChargingData.decode(data)
            all += decoded.rows
            if page * 9999 >= decoded.total { return all }
            guard !decoded.rows.isEmpty else { throw PublicChargingData.failure("충전소 목록 일부를 받지 못했습니다. 다시 조회하세요.") }
        }
        throw PublicChargingData.failure("이 지역의 조회 범위를 초과했습니다. 지역을 다시 선택하세요.")
    }
}
