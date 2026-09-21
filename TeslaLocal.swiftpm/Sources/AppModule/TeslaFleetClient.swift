import Foundation
import Security

/// Tesla official Fleet API endpoints by geographical region and authorization system.
enum FleetRegion: String, CaseIterable, Identifiable {
    case apac = "APAC (한국 / 아시아)"
    case ownerApi = "Owner API (서드파티 토큰)"
    case na = "북미 (NA)"
    case eu = "유럽 (EU)"

    var id: String { rawValue }

    var baseURL: String {
        switch self {
        case .apac: return "https://fleet-api.prd.apac.vn.cloud.tesla.com"
        case .ownerApi: return "https://owner-api.teslamotors.com"
        case .na: return "https://fleet-api.prd.na.vn.cloud.tesla.com"
        case .eu: return "https://fleet-api.prd.eu.vn.cloud.tesla.com"
        }
    }
}

/// Client for remote vehicle data and command communication via Tesla's official Fleet API.
/// Connects over LTE/Internet to wake up vehicle, control climate/seats, trigger remote start,
/// flash lights, honk horn, toggle defrost, lock/unlock, and monitor charging.
/// Supports multi-region auto-fallback (APAC, Owner API, NA, EU) for Korean and global vehicles.
final class TeslaFleetClient: ObservableObject {
    static let shared = TeslaFleetClient()

    @Published var isAuthenticated = false
    @Published var isFetching = false
    @Published var isSendingCommand = false
    @Published var selectedVin: String = ""
    @Published var selectedRegion: FleetRegion = .apac
    @Published var vehicles: [[String: Any]] = []
    @Published var lastRemoteChargeData: [String: Any]?
    @Published var lastError: String?
    @Published var lastSuccessMessage: String?

    private let tokenKey = "TeslaFleetClient.AccessToken"
    private let refreshKey = "TeslaFleetClient.RefreshToken"
    private let vinKey = "TeslaFleetClient.SelectedVin"
    private let regionKey = "TeslaFleetClient.SelectedRegion"

    var currentBaseURL: String {
        selectedRegion.baseURL
    }

    init() {
        isAuthenticated = getStoredToken() != nil
        selectedVin = getStoredVin() ?? ""
        if let storedRegionName = readKeychain(key: regionKey),
           let matched = FleetRegion.allCases.first(where: { $0.rawValue == storedRegionName || $0.id == storedRegionName }) {
            selectedRegion = matched
        } else {
            // Default to APAC for Korea / LRW Shanghai Giga VINs
            selectedRegion = .apac
        }
    }

    // MARK: - Region, Token & VIN Storage (Keychain)

    func saveRegion(_ region: FleetRegion) {
        saveKeychain(key: regionKey, value: region.rawValue)
        DispatchQueue.main.async {
            self.selectedRegion = region
        }
    }

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
            if clean.hasPrefix("LRW") && self.selectedRegion != .apac {
                self.selectedRegion = .apac
                self.saveKeychain(key: self.regionKey, value: FleetRegion.apac.rawValue)
            }
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

    // MARK: - Multi-Region Fallback Engine

    /// Executes network task across candidate regions sequentially with auto-fallback.
    private func executeWithRegionFallback<T>(
        action: (String) async throws -> (T, HTTPURLResponse)
    ) async throws -> T {
        // Priority list: user-selected region first, followed by others
        var candidateRegions: [FleetRegion] = [selectedRegion]
        for region in FleetRegion.allCases where region != selectedRegion {
            candidateRegions.append(region)
        }

        var lastStatusCode = 0
        var attempts: [String] = []

        for region in candidateRegions {
            do {
                let (result, response) = try await action(region.baseURL)
                lastStatusCode = response.statusCode
                if (200...299).contains(response.statusCode) {
                    if self.selectedRegion != region {
                        self.saveRegion(region)
                    }
                    return result
                } else {
                    attempts.append("\(region.rawValue): HTTP \(response.statusCode)")
                }
            } catch {
                attempts.append("\(region.rawValue): \(error.localizedDescription)")
            }
        }

        if lastStatusCode == 401 {
            throw LocalError.message("차량 목록 조회 실패 (HTTP 401). 모든 테슬라 서버(APAC, Owner API, 북미, 유럽)에서 인증 거부되었습니다. 토큰 유효기간이나 스코프를 확인해주세요. (\(attempts.joined(separator: ", ")))")
        }
        throw LocalError.message("테슬라 서버 통신 실패 (\(attempts.joined(separator: "; ")))")
    }

    // MARK: - Fleet API: Vehicles List

    /// Fetches vehicles associated with the authorized Tesla account with automatic regional fallback.
    func fetchVehicles() async throws -> [[String: Any]] {
        guard let token = getStoredToken() else { throw LocalError.message("테슬라 인증 토큰이 설정되지 않았습니다.") }

        return try await executeWithRegionFallback { baseURL in
            let url = URL(string: "\(baseURL)/api/1/vehicles")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LocalError.message("네트워크 응답 오류")
            }

            if (200...299).contains(httpResponse.statusCode) {
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
                return (list, httpResponse)
            }
            return ([], httpResponse)
        }
    }

    // MARK: - Fleet API: Telemetry & State

    /// Wakes up the vehicle if asleep.
    func wakeUp(vin: String? = nil) async throws -> Bool {
        let activeVin = try resolveVin(vin)
        guard let token = getStoredToken() else { throw LocalError.message("테슬라 인증 토큰이 설정되지 않았습니다.") }

        return try await executeWithRegionFallback { baseURL in
            let url = URL(string: "\(baseURL)/api/1/vehicles/\(activeVin)/wake_up")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LocalError.message("네트워크 응답 오류")
            }
            if (200...299).contains(httpResponse.statusCode) {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let res = json?["response"] as? [String: Any]
                let online = (res?["state"] as? String) == "online"
                return (online, httpResponse)
            }
            return (false, httpResponse)
        }
    }

    /// Fetches real-time vehicle charge and state data over LTE.
    func fetchChargeState(vin: String? = nil) async throws -> [String: Any] {
        let activeVin = try resolveVin(vin)
        guard let token = getStoredToken() else { throw LocalError.message("테슬라 인증 토큰이 설정되지 않았습니다.") }

        DispatchQueue.main.async { self.isFetching = true }
        defer { DispatchQueue.main.async { self.isFetching = false } }

        return try await executeWithRegionFallback { baseURL in
            let url = URL(string: "\(baseURL)/api/1/vehicles/\(activeVin)/vehicle_data?endpoints=charge_state;drive_state")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LocalError.message("네트워크 응답 오류")
            }
            if (200...299).contains(httpResponse.statusCode) {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let res = json?["response"] as? [String: Any],
                      let chargeState = res["charge_state"] as? [String: Any] else {
                    throw LocalError.message("충전 데이터 파싱 실패")
                }
                DispatchQueue.main.async {
                    self.lastRemoteChargeData = chargeState
                }
                return (chargeState, httpResponse)
            }
            return ([:], httpResponse)
        }
    }

    // MARK: - Fleet API: Command Transmission Engine

    /// Core helper to dispatch any authenticated command to the Tesla Fleet endpoint with multi-region fallback.
    func sendCommand(vin: String? = nil, command: String, parameters: [String: Any]? = nil) async throws -> Bool {
        let activeVin = try resolveVin(vin)
        guard let token = getStoredToken() else { throw LocalError.message("테슬라 인증 토큰이 설정되지 않았습니다.") }

        DispatchQueue.main.async { self.isSendingCommand = true }
        defer { DispatchQueue.main.async { self.isSendingCommand = false } }

        return try await executeWithRegionFallback { baseURL in
            let url = URL(string: "\(baseURL)/api/1/vehicles/\(activeVin)/command/\(command)")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            if let parameters {
                request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LocalError.message("네트워크 응답 오류")
            }

            if (200...299).contains(httpResponse.statusCode) {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let res = json?["response"] as? [String: Any]
                let success = (res?["result"] as? Bool) ?? true
                if let reason = res?["reason"] as? String, !reason.isEmpty, !success {
                    throw LocalError.message("차량 명령 처리 불가: \(reason)")
                }
                return (success, httpResponse)
            }
            return (false, httpResponse)
        }
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

    /// Sets seat heater level:
    /// heater: 0 (driver front), 1 (passenger front), 2 (rear left), 4 (rear center), 5 (rear right).
    /// level: 0 (Off), 1 (Low), 2 (Medium), 3 (High).
    func setSeatHeater(vin: String? = nil, seatPosition: Int, level: Int) async throws -> Bool {
        try await sendCommand(vin: vin, command: "remote_seat_heater_request", parameters: [
            "heater": seatPosition,
            "level": max(0, min(3, level))
        ])
    }

    /// Sets seat cooler (ventilation) level:
    /// seat_position: 0 (driver front), 1 (passenger front).
    /// seat_cooler_level: 0 (Off), 1 (Low), 2 (Medium), 3 (High).
    func setSeatCooler(vin: String? = nil, seatPosition: Int, level: Int) async throws -> Bool {
        try await sendCommand(vin: vin, command: "remote_seat_cooler_request", parameters: [
            "seat_position": seatPosition,
            "seat_cooler_level": max(0, min(3, level))
        ])
    }

    /// Sets steering wheel heater on/off.
    func setSteeringWheelHeater(vin: String? = nil, on: Bool) async throws -> Bool {
        try await sendCommand(vin: vin, command: "remote_steering_wheel_heater_request", parameters: [
            "on": on
        ])
    }

    /// Sets climate keeper mode: 0 (Off), 1 (Keep), 2 (Dog Mode), 3 (Camp Mode).
    func setClimateKeeperMode(vin: String? = nil, mode: Int) async throws -> Bool {
        try await sendCommand(vin: vin, command: "set_climate_keeper_mode", parameters: [
            "climate_keeper_mode": mode
        ])
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
