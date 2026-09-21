import Foundation
import Security

/// Client for remote vehicle data and command communication via Tesla's official Fleet API.
/// Connects over LTE/Internet to wake up vehicle, control climate/seats, trigger remote start,
/// flash lights, honk horn, toggle defrost, lock/unlock, and monitor charging.
final class TeslaFleetClient: ObservableObject {
    static let shared = TeslaFleetClient()

    @Published var isAuthenticated = false
    @Published var isFetching = false
    @Published var isSendingCommand = false
    @Published var selectedVin: String = ""
    @Published var vehicles: [[String: Any]] = []
    @Published var lastRemoteChargeData: [String: Any]?
    @Published var lastError: String?
    @Published var lastSuccessMessage: String?

    private let baseURL = "https://fleet-api.prd.na.vn.cloud.tesla.com"
    private let tokenKey = "TeslaFleetClient.AccessToken"
    private let refreshKey = "TeslaFleetClient.RefreshToken"
    private let vinKey = "TeslaFleetClient.SelectedVin"

    init() {
        isAuthenticated = getStoredToken() != nil
        selectedVin = getStoredVin() ?? ""
    }

    // MARK: - Token & VIN Storage (Keychain)

    func saveToken(accessToken: String, refreshToken: String? = nil) {
        saveKeychain(key: tokenKey, value: accessToken.trimmingCharacters(in: .whitespacesAndNewlines))
        if let refreshToken {
            saveKeychain(key: refreshKey, value: refreshToken.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        DispatchQueue.main.async {
            self.isAuthenticated = true
        }
    }

    func clearToken() {
        deleteKeychain(key: tokenKey)
        deleteKeychain(key: refreshKey)
        deleteKeychain(key: vinKey)
        DispatchQueue.main.async {
            self.isAuthenticated = false
            self.selectedVin = ""
            self.vehicles = []
            self.lastRemoteChargeData = nil
            self.lastError = nil
        }
    }

    func getStoredToken() -> String? {
        readKeychain(key: tokenKey)
    }

    func saveVin(_ vin: String) {
        let clean = vin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        saveKeychain(key: vinKey, value: clean)
        DispatchQueue.main.async {
            self.selectedVin = clean
        }
    }

    func getStoredVin() -> String? {
        readKeychain(key: vinKey)
    }

    private func resolveVin(_ vin: String?) throws -> String {
        if let vin, !vin.isEmpty { return vin }
        if !selectedVin.isEmpty { return selectedVin }
        if let stored = getStoredVin(), !stored.isEmpty { return stored }
        throw LocalError.message("차량 식별번호(VIN)가 설정되지 않았습니다. 테슬라 계정 설정에서 차량을 선택하거나 VIN을 입력해주세요.")
    }

    // MARK: - Fleet API: Vehicles List

    /// Fetches vehicles associated with the authorized Tesla account.
    func fetchVehicles() async throws -> [[String: Any]] {
        guard let token = getStoredToken() else { throw LocalError.message("테슬라 인증 토큰이 설정되지 않았습니다.") }
        let url = URL(string: "\(baseURL)/api/1/vehicles")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw LocalError.message("차량 목록 조회 실패 (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let list = json?["response"] as? [[String: Any]] else {
            throw LocalError.message("차량 목록 데이터 파싱 오류")
        }
        DispatchQueue.main.async {
            self.vehicles = list
            if self.selectedVin.isEmpty, let firstVin = list.first?["vin"] as? String {
                self.saveVin(firstVin)
            }
        }
        return list
    }

    // MARK: - Fleet API: Telemetry & State

    /// Wakes up the vehicle if asleep.
    func wakeUp(vin: String? = nil) async throws -> Bool {
        let activeVin = try resolveVin(vin)
        guard let token = getStoredToken() else { throw LocalError.message("테슬라 인증 토큰이 설정되지 않았습니다.") }
        let url = URL(string: "\(baseURL)/api/1/vehicles/\(activeVin)/wake_up")!
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
    func fetchChargeState(vin: String? = nil) async throws -> [String: Any] {
        let activeVin = try resolveVin(vin)
        guard let token = getStoredToken() else { throw LocalError.message("테슬라 인증 토큰이 설정되지 않았습니다.") }
        let url = URL(string: "\(baseURL)/api/1/vehicles/\(activeVin)/vehicle_data?endpoints=charge_state;drive_state")!
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

    // MARK: - Fleet API: Command Transmission Engine

    /// Core helper to dispatch any authenticated command to the Tesla Fleet endpoint.
    func sendCommand(vin: String? = nil, command: String, parameters: [String: Any]? = nil) async throws -> Bool {
        let activeVin = try resolveVin(vin)
        guard let token = getStoredToken() else { throw LocalError.message("테슬라 인증 토큰이 설정되지 않았습니다.") }
        let url = URL(string: "\(baseURL)/api/1/vehicles/\(activeVin)/command/\(command)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let parameters {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        }

        DispatchQueue.main.async { self.isSendingCommand = true }
        defer { DispatchQueue.main.async { self.isSendingCommand = false } }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalError.message("네트워크 응답 오류")
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let errorMsg: String
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["error"] as? String {
                errorMsg = "명령 거부 (\(err))"
            } else {
                errorMsg = "원격 명령 전송 실패 (HTTP \(httpResponse.statusCode))"
            }
            throw LocalError.message(errorMsg)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let res = json?["response"] as? [String: Any]
        let success = (res?["result"] as? Bool) ?? true
        if let reason = res?["reason"] as? String, !reason.isEmpty, !success {
            throw LocalError.message("차량 명령 처리 불가: \(reason)")
        }
        return success
    }

    // MARK: - Specific High-Level Fleet Commands

    /// Enables Keyless Driving (Remote Start) for 2 minutes over LTE.
    func remoteStartDrive(vin: String? = nil, password: String? = nil) async throws -> Bool {
        var params: [String: Any] = [:]
        if let password, !password.isEmpty {
            params["password"] = password
        }
        return try await sendCommand(vin: vin, command: "remote_start_drive", parameters: params.isEmpty ? nil : params)
    }

    /// Flashes headlights to locate vehicle.
    func flashLights(vin: String? = nil) async throws -> Bool {
        try await sendCommand(vin: vin, command: "flash_lights")
    }

    /// Honks horn.
    func honkHorn(vin: String? = nil) async throws -> Bool {
        try await sendCommand(vin: vin, command: "honk_horn")
    }

    /// Locks vehicle doors.
    func doorLock(vin: String? = nil) async throws -> Bool {
        try await sendCommand(vin: vin, command: "door_lock")
    }

    /// Unlocks vehicle doors.
    func doorUnlock(vin: String? = nil) async throws -> Bool {
        try await sendCommand(vin: vin, command: "door_unlock")
    }

    /// Actuates frunk or trunk ("front" or "rear").
    func actuateTrunk(vin: String? = nil, whichTrunk: String) async throws -> Bool {
        try await sendCommand(vin: vin, command: "actuate_trunk", parameters: ["which_trunk": whichTrunk])
    }

    /// Turns climate on or off over LTE.
    func setAutoConditioning(vin: String? = nil, on: Bool) async throws -> Bool {
        try await sendCommand(vin: vin, command: on ? "auto_conditioning_start" : "auto_conditioning_stop")
    }

    /// Sets driver & passenger target temperatures (°C).
    func setTemps(vin: String? = nil, driverTemp: Double, passengerTemp: Double) async throws -> Bool {
        try await sendCommand(vin: vin, command: "set_temps", parameters: [
            "driver_temp": driverTemp,
            "passenger_temp": passengerTemp
        ])
    }

    /// Enables or disables maximum windshield defrost and battery preconditioning.
    func setPreconditioningMax(vin: String? = nil, on: Bool) async throws -> Bool {
        try await sendCommand(vin: vin, command: "set_preconditioning_max", parameters: [
            "on": on,
            "manual_override_mode": false
        ])
    }

    /// Opens or closes the charge port door.
    func chargePortDoor(vin: String? = nil, open: Bool) async throws -> Bool {
        try await sendCommand(vin: vin, command: open ? "charge_port_door_open" : "charge_port_door_close")
    }

    /// Sends remote charge commands (charge_start, charge_stop, set_charge_limit).
    func sendChargeCommand(vin: String? = nil, command: String, value: Int? = nil) async throws -> Bool {
        var params: [String: Any]? = nil
        if let value, command == "set_charge_limit" {
            params = ["percent": value]
        }
        return try await sendCommand(vin: vin, command: command, parameters: params)
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
