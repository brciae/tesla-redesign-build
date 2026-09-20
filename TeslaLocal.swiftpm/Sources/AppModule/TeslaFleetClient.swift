import Foundation
import Security

/// Client for remote vehicle data and command communication via Tesla's official Fleet API.
/// Allows checking real-time charging status, waking up vehicle, and issuing charge commands over LTE/Internet.
final class TeslaFleetClient: ObservableObject {
    static let shared = TeslaFleetClient()

    @Published var isAuthenticated = false
    @Published var isFetching = false
    @Published var lastRemoteChargeData: [String: Any]?
    @Published var lastError: String?

    private let baseURL = "https://fleet-api.prd.na.vn.cloud.tesla.com"
    private let tokenKey = "TeslaFleetClient.AccessToken"
    private let refreshKey = "TeslaFleetClient.RefreshToken"

    init() {
        isAuthenticated = getStoredToken() != nil
    }

    // MARK: - Token Storage (Keychain)

    func saveToken(accessToken: String, refreshToken: String? = nil) {
        saveKeychain(key: tokenKey, value: accessToken)
        if let refreshToken {
            saveKeychain(key: refreshKey, value: refreshToken)
        }
        DispatchQueue.main.async {
            self.isAuthenticated = true
        }
    }

    func clearToken() {
        deleteKeychain(key: tokenKey)
        deleteKeychain(key: refreshKey)
        DispatchQueue.main.async {
            self.isAuthenticated = false
            self.lastRemoteChargeData = nil
        }
    }

    func getStoredToken() -> String? {
        readKeychain(key: tokenKey)
    }

    // MARK: - Remote Vehicle Operations

    /// Wakes up the vehicle if asleep.
    func wakeUp(vin: String) async throws -> Bool {
        guard let token = getStoredToken() else { throw LocalError.message("테슬라 인증 토큰이 설정되지 않았습니다.") }
        let url = URL(string: "\(baseURL)/api/1/vehicles/\(vin)/wake_up")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw LocalError.message("차량 깨우기 실패")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let res = json?["response"] as? [String: Any]
        return (res?["state"] as? String) == "online"
    }

    /// Fetches real-time vehicle charge and state data over LTE.
    func fetchChargeState(vin: String) async throws -> [String: Any] {
        guard let token = getStoredToken() else { throw LocalError.message("테슬라 인증 토큰이 설정되지 않았습니다.") }
        let url = URL(string: "\(baseURL)/api/1/vehicles/\(vin)/vehicle_data?endpoints=charge_state;drive_state")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        DispatchQueue.main.async { self.isFetching = true }
        defer { DispatchQueue.main.async { self.isFetching = false } }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw LocalError.message("원격 데이터 조회 실패 (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let res = json?["response"] as? [String: Any],
              let chargeState = res["charge_state"] as? [String: Any] else {
            throw LocalError.message("충전 데이터 파싱 실패")
        }

        DispatchQueue.main.async {
            self.lastRemoteChargeData = chargeState
        }
        return chargeState
    }

    /// Sends remote charge commands (charge_start, charge_stop, set_charge_limit).
    func sendChargeCommand(vin: String, command: String, value: Int? = nil) async throws -> Bool {
        guard let token = getStoredToken() else { throw LocalError.message("테슬라 인증 토큰이 설정되지 않았습니다.") }
        let url = URL(string: "\(baseURL)/api/1/vehicles/\(vin)/command/\(command)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let value, command == "set_charge_limit" {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["percent": value])
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw LocalError.message("원격 명령 전송 실패")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let res = json?["response"] as? [String: Any]
        return (res?["result"] as? Bool) ?? false
    }

    // MARK: - Keychain Helpers

    private func saveKeychain(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func readKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    private func deleteKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
