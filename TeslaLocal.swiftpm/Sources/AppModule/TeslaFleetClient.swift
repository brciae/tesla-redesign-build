import Foundation
import Combine
import Security
import CryptoKit

/// Tesla official Fleet API endpoints by geographical region and authorization system.
enum FleetRegion: String, CaseIterable, Identifiable {
    case apac = "APAC (한국 / 아시아)"
    case ownerApi = "Owner API (서드파티 토큰)"
    case na = "북미 (NA)"
    case eu = "유럽 (EU)"

    var id: String { rawValue }

    var baseURL: String {
        switch self {
        case .apac: return FleetAuthPolicy.asiaPacificURL
        case .ownerApi: return "https://owner-api.teslamotors.com"
        case .na: return "https://fleet-api.prd.na.vn.cloud.tesla.com"
        case .eu: return "https://fleet-api.prd.eu.vn.cloud.tesla.com"
        }
    }
}

/// Client for remote vehicle data and command communication via Tesla's official Fleet API.
/// Connects over LTE/Internet to wake up vehicle, control climate/seats, trigger remote start,
/// flash lights, honk horn, toggle defrost, lock/unlock, and monitor charging.
/// Uses only the selected API region; requests are never replayed across servers.
final class TeslaFleetClient: ObservableObject {
    static let shared = TeslaFleetClient()

    @Published var isAuthenticated = false
    @Published var isFetching = false
    @Published var isSendingCommand = false
    @Published var commandStatus = "원격 제어 준비 확인 필요"
    var onCommandFailure: ((String) -> Void)?
    var commandAllowed: (() -> Bool)?
    var commandProxy: String { UserDefaults.standard.string(forKey: "fleetCommandProxy") ?? "" }
    func saveCommandProxy(_ text: String) throws {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { _ = try FleetCommandPolicy.proxyURL(clean) }
        UserDefaults.standard.set(clean, forKey: "fleetCommandProxy")
        commandStatus = clean.isEmpty ? "명령 서명 서버 미설정" : "서명 서버 저장됨 · 차량 가상키 등록 확인 필요"
    }
    @Published var selectedVin: String = ""
    @Published var selectedRegion: FleetRegion = .apac
    @Published var vehicles: [[String: Any]] = []
    @Published var lastRemoteChargeData: [String: Any]?
    @Published var lastError: String?
    @Published var lastSuccessMessage: String?
    @Published var vehicleSnapshot: FleetVehicleSnapshot?
    @Published var vehicleReadStatus = "차량 미조회"
    @Published var vehicleReadError: String?
    @Published var isReadingVehicle = false
    private var lastVehicleRead = Date.distantPast
    private var vehicleReadID = UUID()
    var vehicleDisplayStatus: String {
        if vehicleReadStatus == "Fleet 상태 수신", vehicleSnapshot?.isRecent() != true { return "Fleet 마지막 수신" }
        return vehicleReadStatus
    }

    private let tokenKey = "TeslaFleetClient.AccessToken"
    private let refreshKey = "TeslaFleetClient.RefreshToken"
    private let refreshClientKey = "TeslaFleetClient.RefreshClientId"
    @MainActor private var refreshTask: Task<String, Error>?
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
            // Korea uses the NA Fleet endpoint under the APAC display label.
            selectedRegion = .apac
        }
    }

    // MARK: - Tesla Developer OAuth 2.0 Configuration & Token Exchange
    static let defaultClientId = "c469b20e-546a-452e-a151-58768a89ac7c"
    static let defaultRedirectUri = "https://brciae.github.io/callback"

    private let clientIdKey = "TeslaFleetClient.ClientId"
    private let redirectUriKey = "TeslaFleetClient.RedirectUri"
    private let clientSecretKey = "TeslaFleetClient.ClientSecret"
    private let oauthStateKey = "TeslaFleetClient.OAuthState"
    private let oauthClientKey = "TeslaFleetClient.OAuthClient"
    private let oauthRedirectKey = "TeslaFleetClient.OAuthRedirect"
    private let oauthAudienceKey = "TeslaFleetClient.OAuthAudience"
    private let codeVerifierKey = "TeslaFleetClient.CodeVerifier"

    func getClientId() -> String {
        readKeychain(key: clientIdKey) ?? Self.defaultClientId
    }

    func saveClientId(_ id: String) {
        let clean = id.trimmingCharacters(in: .whitespacesAndNewlines)
        saveKeychain(key: clientIdKey, value: clean.isEmpty ? Self.defaultClientId : clean)
    }

    func getRedirectUri() -> String {
        readKeychain(key: redirectUriKey) ?? Self.defaultRedirectUri
    }

    func saveRedirectUri(_ uri: String) {
        let clean = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        saveKeychain(key: redirectUriKey, value: clean.isEmpty ? Self.defaultRedirectUri : clean)
    }

    func getClientSecret() -> String? {
        readKeychain(key: clientSecretKey)
    }

    func saveClientSecret(_ secret: String) {
        let clean = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            deleteKeychain(key: clientSecretKey)
        } else {
            saveKeychain(key: clientSecretKey, value: clean)
        }
    }

    // MARK: - RFC 7636 PKCE Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        let hashed = SHA256.hash(data: data)
        return Data(hashed)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    /// Generates a fresh PKCE code verifier and builds the Tesla OAuth 2.0 Web Authorize URL for the user's browser.
    func startWebAuthorization() -> URL? {
        guard let secret = getClientSecret(), !secret.isEmpty else {
            lastError = "개발자 앱의 Client Secret이 필요합니다. 테슬라 계정 비밀번호가 아닙니다."
            return nil
        }
        guard selectedRegion != .ownerApi else {
            lastError = "공식 로그인은 Fleet 리전을 선택해 주세요. 한국은 APAC/NA 서버를 사용합니다."
            return nil
        }
        let state = UUID().uuidString
        saveKeychain(key: oauthStateKey, value: state)
        saveKeychain(key: oauthClientKey, value: getClientId())
        saveKeychain(key: oauthRedirectKey, value: getRedirectUri())
        saveKeychain(key: oauthAudienceKey, value: currentBaseURL)
        let verifier = generateCodeVerifier()
        saveKeychain(key: codeVerifierKey, value: verifier)
        guard readKeychain(key: oauthStateKey) == state,
              readKeychain(key: codeVerifierKey) == verifier,
              readKeychain(key: oauthClientKey) == getClientId(),
              readKeychain(key: oauthRedirectKey) == getRedirectUri(),
              readKeychain(key: oauthAudienceKey) == currentBaseURL else {
            lastError = "로그인 세션을 Keychain에 저장하지 못했습니다. 앱 서명과 기기 잠금 해제 상태 확인 필요."
            return nil
        }
        let challenge = generateCodeChallenge(from: verifier)
        return buildAuthorizeURL(challenge: challenge)
    }

    /// Generates the official Tesla OAuth 2.0 Web Authorize URL with PKCE (S256).
    private func buildAuthorizeURL(challenge: String? = nil) -> URL? {
        let cid = getClientId()
        let rUri = getRedirectUri()
        var components = URLComponents(string: "https://auth.tesla.com/oauth2/v3/authorize")

        let activeChallenge: String
        if let challenge, !challenge.isEmpty {
            activeChallenge = challenge
        } else if let storedVerifier = readKeychain(key: codeVerifierKey), !storedVerifier.isEmpty {
            activeChallenge = generateCodeChallenge(from: storedVerifier)
        } else {
            let newVerifier = generateCodeVerifier()
            saveKeychain(key: codeVerifierKey, value: newVerifier)
            activeChallenge = generateCodeChallenge(from: newVerifier)
        }

        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: cid),
            URLQueryItem(name: "redirect_uri", value: rUri),
            URLQueryItem(name: "scope", value: "openid offline_access vehicle_device_data vehicle_cmds vehicle_charging_cmds"),
            URLQueryItem(name: "state", value: readKeychain(key: oauthStateKey) ?? ""),
            URLQueryItem(name: "prompt", value: "login"),
            URLQueryItem(name: "code_challenge", value: activeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return components?.url
    }

    /// Exchanges an OAuth 2.0 Authorization Code for official Bearer Access & Refresh Tokens.
    @discardableResult
    @MainActor func exchangeAuthorizationCode(code: String) async throws -> [String: Any] {
        guard let state = readKeychain(key: oauthStateKey),
              let cid = readKeychain(key: oauthClientKey),
              let rUri = readKeychain(key: oauthRedirectKey),
              let audience = readKeychain(key: oauthAudienceKey),
              let verifier = readKeychain(key: codeVerifierKey),
              let secret = getClientSecret(), !secret.isEmpty else {
            throw FleetAuthPolicy.failure("새 로그인 세션이 필요합니다. 개발자 앱 설정 후 1단계부터 진행해 주세요.")
        }
        guard cid == getClientId(), rUri == getRedirectUri() else {
            throw FleetAuthPolicy.failure("로그인 중 앱 설정이 변경됐습니다. 새로 로그인해 주세요.")
        }
        let cleanCode = try FleetAuthPolicy.callbackCode(code, redirect: rUri, state: state)
        // Consume locally before the first suspension: a code must never be sent twice.
        deleteKeychain(key: oauthStateKey)
        deleteKeychain(key: codeVerifierKey)
        guard readKeychain(key: oauthStateKey) == nil, readKeychain(key: codeVerifierKey) == nil else {
            throw FleetAuthPolicy.failure("로그인 세션을 안전하게 종료하지 못했습니다. 앱 서명 설정 확인 필요.")
        }
        let tokenURL = FleetAuthPolicy.tokenURL

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyParams = [
            "grant_type": "authorization_code",
            "client_id": cid,
            "code": cleanCode,
            "redirect_uri": rUri,
            "audience": audience
        ]
        bodyParams["code_verifier"] = verifier
        bodyParams["client_secret"] = secret
        request.httpBody = FleetAuthPolicy.formBody(bodyParams)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalError.message("테슬라 인증 서버 응답 없음")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalError.message("토큰 응답 해석 실패 (HTTP \(httpResponse.statusCode)). 새로 로그인해 주세요.")
        }

        if let error = json["error"] as? String {
            if error == "invalid_auth_code" || error == "invalid_grant" {
                throw FleetAuthPolicy.failure("인증 코드가 만료됐거나 이미 사용됐습니다. 1단계에서 새로 로그인한 후 새 전체 URL을 붙여넣어 주세요.")
            }
            throw FleetAuthPolicy.failure("테슬라 OAuth 실패: \(error). 개발자 앱 설정과 권한 확인 후 새로 로그인해 주세요.")
        }

        guard (200...299).contains(httpResponse.statusCode),
              let accessToken = json["access_token"] as? String, !accessToken.isEmpty else {
            throw LocalError.message("응답에 access_token이 없습니다.")
        }

        let refreshToken = json["refresh_token"] as? String
        saveToken(accessToken: accessToken, refreshToken: refreshToken)
        saveKeychain(key: refreshClientKey, value: cid)
        guard getStoredToken() == accessToken else {
            isAuthenticated = false
            throw FleetAuthPolicy.failure("인증은 완료됐지만 토큰을 Keychain에 저장하지 못했습니다. 앱 서명 설정 확인 필요.")
        }

        DispatchQueue.main.async {
            self.lastSuccessMessage = "테슬라 공식 계정 로그인 성공! (OAuth 2.0)"
            self.lastError = nil
        }

        return json
    }

    // MARK: - Region, Token & VIN Storage (Keychain)

    @MainActor private func authenticatedToken() async throws -> String {
        guard let token = getStoredToken() else { throw FleetAuthPolicy.failure("테슬라 로그인이 필요합니다.") }
        guard FleetAuthPolicy.needsRefresh(token) else { return token }
        if let refreshTask { return try await refreshTask.value }
        guard let refresh = readKeychain(key: refreshKey),
              let client = readKeychain(key: refreshClientKey), client == getClientId() else {
            isAuthenticated = false
            throw FleetAuthPolicy.failure("토큰이 만료됐습니다. 현재 개발자 앱으로 새로 로그인해 주세요.")
        }
        let task = Task { @MainActor [self] () async throws -> String in
            var request = URLRequest(url: FleetAuthPolicy.tokenURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = FleetAuthPolicy.formBody(["grant_type": "refresh_token", "client_id": client, "refresh_token": refresh])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard getStoredToken() == token, readKeychain(key: refreshKey) == refresh else {
                throw CancellationError()
            }
            guard (200...299).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let access = json["access_token"] as? String, !access.isEmpty,
                  let rotated = json["refresh_token"] as? String, !rotated.isEmpty else {
                if http.statusCode == 400 || http.statusCode == 401 {
                    deleteKeychain(key: refreshKey)
                    isAuthenticated = false
                }
                throw FleetAuthPolicy.failure("테슬라 토큰 갱신 실패 (HTTP \(http.statusCode)). 새 로그인 또는 서버 상태 확인 필요.")
            }
            saveToken(accessToken: access, refreshToken: rotated)
            guard getStoredToken() == access, readKeychain(key: refreshKey) == rotated else {
                throw FleetAuthPolicy.failure("갱신된 토큰 저장 실패. 새로 로그인해 주세요.")
            }
            return access
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    func saveRegion(_ region: FleetRegion) {
        saveKeychain(key: regionKey, value: region.rawValue)
        DispatchQueue.main.async {
            self.selectedRegion = region
        }
    }

    func saveToken(accessToken: String, refreshToken: String? = nil) {
        let preserveRefresh = FleetAuthPolicy.preservesRefreshToken(storedAccess: getStoredToken(), incomingAccess: accessToken)
        saveKeychain(key: tokenKey, value: accessToken.trimmingCharacters(in: .whitespacesAndNewlines))
        if let refreshToken {
            saveKeychain(key: refreshKey, value: refreshToken.trimmingCharacters(in: .whitespacesAndNewlines))
        } else if !preserveRefresh {
            deleteKeychain(key: refreshKey)
            deleteKeychain(key: refreshClientKey)
        }
        let persisted = getStoredToken() == accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.main.async { self.isAuthenticated = persisted }
    }

    func clearToken() {
        deleteKeychain(key: oauthStateKey)
        deleteKeychain(key: codeVerifierKey)
        deleteKeychain(key: tokenKey)
        deleteKeychain(key: refreshKey)
        deleteKeychain(key: refreshClientKey)
        deleteKeychain(key: vinKey)
        DispatchQueue.main.async {
            self.vehicleReadID = UUID()
            self.vehicleSnapshot = nil
            self.vehicleReadStatus = "로그인 필요"
            self.vehicleReadError = nil
            self.lastVehicleRead = .distantPast
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
            let changed = self.selectedVin != clean
            self.selectedVin = clean
            if changed {
                self.vehicleReadID = UUID()
                self.vehicleSnapshot = nil
                self.lastVehicleRead = .distantPast
            }
            Task { @MainActor in await self.refreshVehicleSnapshot() }
        }
    }

    /// Refresh on login/selection/foreground/manual request, never a background polling loop.
    @MainActor func refreshVehicleSnapshot(force: Bool = false) async {
        guard getStoredToken() != nil else { return }
        guard !isReadingVehicle else { return }
        guard force || Date().timeIntervalSince(lastVehicleRead) >= 30 else { return }
        isReadingVehicle = true
        let requestID = UUID(); vehicleReadID = requestID
        vehicleReadError = nil; vehicleReadStatus = "차량 조회 중"
        lastVehicleRead = Date()
        defer {
            isReadingVehicle = false
            // A selected vehicle can change while a previous request is in flight.
            if vehicleReadID != requestID, getStoredToken() != nil {
                Task { @MainActor in await self.refreshVehicleSnapshot() }
            }
        }
        do {
            var vin = getStoredVin() ?? ""
            if vin.isEmpty {
                let list = try await fetchVehicles()
                guard let first = list.first?["vin"] as? String else {
                    throw FleetAuthPolicy.failure("로그인은 완료됐지만 조회 가능한 차량이 없습니다. 차량 공유·앱 권한 확인 필요.")
                }
                vin = first
                saveKeychain(key: vinKey, value: vin)
                selectedVin = vin
            }
            let requestVin = vin
            let token = try await authenticatedToken()
            let base = currentBaseURL
            func read(_ path: String) async throws -> [String: Any] {
                var request = URLRequest(url: URL(string: base + path)!)
                request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 25
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                guard (200...299).contains(http.statusCode) else {
                    throw FleetAuthPolicy.apiFailure(status: http.statusCode, data: data, stage: path.contains("vehicle_data") ? "차량 상세 조회" : "차량 상태 조회", secrets: [token, requestVin])
                }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let result = json["response"] as? [String: Any] else {
                    throw FleetAuthPolicy.failure("차량 응답 형식 확인 필요")
                }
                return result
            }
            let vehicle = try await read("/api/1/vehicles/\(requestVin)")
            guard vehicleReadID == requestID, getStoredVin() == requestVin, getStoredToken() == token else { return }
            let status = vehicle["state"] as? String ?? "unknown"
            if status != "online" {
                vehicleReadStatus = status == "asleep" ? "차량 절전 중" : "차량 오프라인"
                return
            }
            let data = try await read("/api/1/vehicles/\(requestVin)/vehicle_data?endpoints=charge_state;climate_state;vehicle_state;drive_state")
            guard vehicleReadID == requestID, getStoredVin() == requestVin, getStoredToken() == token else { return }
            if let returnedVin = data["vin"] as? String, returnedVin != requestVin {
                throw FleetAuthPolicy.failure("선택 차량과 응답 차량이 다릅니다. 차량 재선택 필요.")
            }
            let snapshot = FleetVehicleSnapshot(vin: requestVin, receivedAt: Date(), payload: data)
            guard snapshot.hasMeasurements else { throw FleetAuthPolicy.failure("차량은 온라인이나 상태 데이터가 비어 있습니다. 데이터 권한 확인 필요.") }
            vehicleSnapshot = snapshot
            SmartParkingManager.shared.observeFleet(snapshot)
            lastRemoteChargeData = data["charge_state"] as? [String: Any]
            vehicleReadStatus = snapshot.isRecent() ? "Fleet 상태 수신" : "Fleet 저장값 수신"
        } catch {
            guard vehicleReadID == requestID else { return }
            vehicleReadStatus = "차량 조회 실패"
            vehicleReadError = error.localizedDescription
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

    // MARK: - Selected Region Requests

    /// Explicit developer setup only. The partner token never replaces user OAuth credentials.
    @MainActor func registerPartnerAccount() async throws {
        guard selectedRegion != .ownerApi else { throw FleetAuthPolicy.failure("공식 Fleet 리전을 선택해 주세요.") }
        guard let secret = getClientSecret(), !secret.isEmpty else { throw FleetAuthPolicy.failure("개발자 앱의 Client Secret을 먼저 입력해 주세요.") }
        guard let redirect = URL(string: getRedirectUri()), redirect.scheme == "https", let domain = redirect.host else {
            throw FleetAuthPolicy.failure("개발자 앱에 등록된 HTTPS 리다이렉트 주소가 필요합니다.")
        }
        let base = currentBaseURL
        let client = getClientId()
        var tokenRequest = URLRequest(url: FleetAuthPolicy.tokenURL)
        tokenRequest.httpMethod = "POST"
        tokenRequest.timeoutInterval = 30
        tokenRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        tokenRequest.httpBody = FleetAuthPolicy.formBody(["grant_type": "client_credentials", "client_id": client, "client_secret": secret, "audience": base])
        let (tokenData, tokenResponse) = try await URLSession.shared.data(for: tokenRequest)
        guard let tokenHTTP = tokenResponse as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(tokenHTTP.statusCode) else {
            throw FleetAuthPolicy.apiFailure(status: tokenHTTP.statusCode, data: tokenData, stage: "개발자 인증", secrets: [secret, client])
        }
        guard let json = try JSONSerialization.jsonObject(with: tokenData) as? [String: Any], let partnerToken = json["access_token"] as? String, !partnerToken.isEmpty else {
            throw FleetAuthPolicy.failure("개발자 인증 응답에 토큰이 없습니다.")
        }
        var request = URLRequest(url: URL(string: base + "/api/1/partner_accounts")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer " + partnerToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["domain": domain])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            throw FleetAuthPolicy.apiFailure(status: http.statusCode, data: data, stage: "개발자 앱 등록", secrets: [secret, client, partnerToken])
        }
        lastSuccessMessage = "개발자 앱 등록 응답 수신 · " + domain
        lastError = nil
    }

    /// Executes each request once against the selected API region.
    private func executeWithRegionFallback<T>(
        action: (String) async throws -> (T, HTTPURLResponse)
    ) async throws -> T {
        // Never replay requests or send a Fleet token to a different API family.
        let (result, response) = try await action(currentBaseURL)
        guard (200...299).contains(response.statusCode) else {
            let help = response.statusCode == 401 ? "토큰 만료 또는 인증 실패: 새 로그인 필요" : "앱 등록·권한·선택 리전 확인 필요"
            throw LocalError.message("테슬라 HTTP \(response.statusCode): \(help)")
        }
        return result
    }

    // MARK: - Fleet API: Vehicles List

    /// Fetches vehicles associated with the authorized Tesla account with automatic regional fallback.
    func fetchVehicles() async throws -> [[String: Any]] {
        let token = try await authenticatedToken()

        return try await executeWithRegionFallback { baseURL in
            let url = URL(string: "\(baseURL)/api/1/vehicles")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

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
                    if !list.contains(where: { $0["vin"] as? String == self.selectedVin }), let firstVin = list.first?["vin"] as? String {
                        self.saveVin(firstVin)
                    }
                }
                return (list, httpResponse)
            }
            throw FleetAuthPolicy.apiFailure(status: httpResponse.statusCode, data: data, stage: "차량 목록 조회", secrets: [token])
        }
    }

    // MARK: - Fleet API: Telemetry & State

    /// Wakes up the vehicle if asleep.
    func wakeUp(vin: String? = nil) async throws -> Bool {
        let activeVin = try resolveVin(vin)
        let token = try await authenticatedToken()

        return try await executeWithRegionFallback { baseURL in
            let url = URL(string: "\(baseURL)/api/1/vehicles/\(activeVin)/wake_up")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
            throw FleetAuthPolicy.apiFailure(status: httpResponse.statusCode, data: data, stage: "차량 깨우기", secrets: [token, activeVin])
        }
    }

    /// Fetches real-time vehicle charge and state data over LTE.
    func fetchChargeState(vin: String? = nil) async throws -> [String: Any] {
        let activeVin = try resolveVin(vin)
        let token = try await authenticatedToken()

        DispatchQueue.main.async { self.isFetching = true }
        defer { DispatchQueue.main.async { self.isFetching = false } }

        return try await executeWithRegionFallback { baseURL in
            let url = URL(string: "\(baseURL)/api/1/vehicles/\(activeVin)/vehicle_data?endpoints=charge_state;drive_state")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

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
            throw FleetAuthPolicy.apiFailure(status: httpResponse.statusCode, data: data, stage: "충전 상태 조회", secrets: [token, activeVin])
        }
    }

    // MARK: - Fleet API: Command Transmission Engine

    /// Core helper to dispatch any authenticated command to the Tesla Fleet endpoint with multi-region fallback.
    @MainActor func sendCommand(vin: String? = nil, command: String, parameters: [String: Any]? = nil) async throws -> Bool {
        do {
            guard commandAllowed?() == true else { throw FleetCommandPolicy.failure("현재 상태에서는 차량 제어할 수 없습니다. 데모를 종료하고 앱을 열어 확인하세요.") }
            guard !isSendingCommand else { throw FleetCommandPolicy.failure("앞선 명령의 응답을 기다리는 중입니다.") }
            isSendingCommand = true
            defer { isSendingCommand = false }
            let activeVin = try resolveVin(vin)
            let base = try FleetCommandPolicy.proxyURL(commandProxy)
            let token = try await authenticatedToken()
            guard commandAllowed?() == true, activeVin == (vin ?? selectedVin) else { throw FleetCommandPolicy.failure("차량 또는 앱 상태가 변경되어 전송을 중단했습니다.") }
            let url = base.appendingPathComponent("api/1/vehicles").appendingPathComponent(activeVin).appendingPathComponent("command").appendingPathComponent(command)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            if let parameters {
                request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
            }

            commandStatus = "원격 명령 전송 중"
            let session = URLSession(configuration: .ephemeral, delegate: FleetCommandRedirectGuard(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LocalError.message("네트워크 응답 오류")
            }

            if (200...299).contains(httpResponse.statusCode) {
                let success = try FleetCommandPolicy.accepted(data)
                commandStatus = "차량 명령 승인 응답 수신"
                await refreshVehicleSnapshot(force: true)
                return success
            }
            throw FleetAuthPolicy.apiFailure(status: httpResponse.statusCode, data: data, stage: "차량 명령", secrets: [token, activeVin])
        } catch {
            commandStatus = error.localizedDescription
            onCommandFailure?(error.localizedDescription)
            throw error
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
            kSecAttrAccount as String: key
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
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
