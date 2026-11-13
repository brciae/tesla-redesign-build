import Foundation
import Security
import CryptoKit

/// Explicit reusable configuration only. No OAuth session, device key, permission or NAS password.
enum NASConfigurationVault {
    struct Snapshot: Codable, Equatable {
        var version = 1
        var entries: [String: String] = [:]
    }
    struct Envelope: Codable { let revision: Int; let sealed: String }
    struct Credential {
        let id: String
        let service: String?
        let account: String
        var accessibility: CFString {
            account.hasPrefix("TeslaFleetClient.") ? kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly : kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        var query: [String: Any] {
            var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account]
            if let service { q[kSecAttrService as String] = service }
            return q
        }
    }
    static let credentials: [Credential] = [
        .init(id: "tesla.clientID", service: nil, account: "TeslaFleetClient.ClientId"),
        .init(id: "tesla.redirect", service: nil, account: "TeslaFleetClient.RedirectUri"),
        .init(id: "tesla.region", service: nil, account: "TeslaFleetClient.SelectedRegion"),
        .init(id: "tesla.secret", service: nil, account: "TeslaFleetClient.ClientSecret"),
        .init(id: "kakao", service: "YLCompanion.KakaoNavigation", account: "nativeAppKey"),
        .init(id: "charging", service: "YL.public.charging", account: "data.go.kr")
    ] + ["OpenAI", "Claude", "Gemini"].map { .init(id: "ai." + $0, service: "YL.automation.api", account: $0) }

    // Keep this allowlist separate from ordinary, unencrypted JSON exports.
    static let preferences = ["fleetCommandProxy", "spotify.clientID", "typecastApiKeys", "typecastActiveKeyIndex",
        "typecastVoiceId", "typecastEnabled", "cost.gasoline", "cost.gasolineEfficiency", "cost.electricity",
        "automationAPI.provider", "automationSpeech.skipRoutine", "backgroundBLERead", "appearance", "embeddedNavigationEnabled", "diagnostics.suspend3D",
        "autoDrivingDashboard", "character.finish", "character.id", "characterChat.enabled", "characterChat.floatingCharacter",
        "characterFloat.finish", "characterFloat.id", "characterFloat.scale", "characterFloat.voice", "characterFloat.x", "characterFloat.y",
        "charging.favorites.v1", "charging.public.region", "energy.saving", "energy.section", "exitClock",
        "handOffToNaver", "highway", "liveActivityEnabled", "navSafetyVoice", "navVoiceDetail", "navVoiceEnabled", "navVoiceVolume",
        "navigation.autoTrafficReroute", "navigation.dashboardShade", "navigation.floatingCard", "navigation.focusMode",
        "navigation.home", "navigation.mapAppearance", "navigation.markerScale", "navigation.markerStyle", "navigation.recent",
        "navigation.routePriority", "navigationHipass", "navigationOrientation", "navigationTheme",
        "notify.automation", "notify.charge.complete", "notify.charge.limit", "notify.charge.start", "notify.charge.stop", "notify.trip.end",
        "overspeed.beep", "overspeed.distance", "overspeed.sound", "overspeed.volume", "preferredMapEngine", "running.footsteps",
        "tabBarOpacity", "teslamate.section", "teslamate.usage.calendar", "typecast.favorites", "typecast.filter.age",
        "typecast.filter.category", "typecast.filter.favorites", "typecast.filter.gender", "unitDistance", "unitPressure", "unitTemperature",
        "voiceAutomations", "voiceBriefDetail", "voiceConnection", "voiceControl", "voiceDeliveryStyle", "voiceDuck", "voiceEnabled",
        "voiceIdentifier", "voiceOutput", "voiceQuietEnabled", "voiceQuietEnd", "voiceQuietStart", "voiceRate", "voiceVolume",
        "voiceTrip", "voiceCharge", "voiceBattery", "voiceDestination", "voicePitch", "keepDriveDisplayOn"]
    static let preferencePrefixes = ["appearance.v1.", "vehicle.reference.", "automationAPI.model.", "warranty.start."]
    static func allowedPreference(_ name: String) -> Bool {
        preferences.contains(name) || preferencePrefixes.contains(where: name.hasPrefix)
    }
    private enum PreferenceValue: Codable {
        case text(String), data(Data), date(Date), boolean(Bool), integer(Int64), number(Double)
        case array([PreferenceValue]), object([String: PreferenceValue])
        init(_ value: Any) throws {
            if let text = value as? String { self = .text(text) }
            else if let data = value as? Data { self = .data(data) }
            else if let date = value as? Date { self = .date(date) }
            else if let value = value as? NSNumber {
                if CFGetTypeID(value) == CFBooleanGetTypeID() { self = .boolean(value.boolValue) }
                else if ["f", "d"].contains(String(cString: value.objCType)) { self = .number(value.doubleValue) }
                else { self = .integer(value.int64Value) }
            }
            else if let array = value as? [Any] { self = .array(try array.map { try Self($0) }) }
            else if let object = value as? [String: Any] { self = .object(try object.mapValues { try Self($0) }) }
            else { throw NASConfigurationVault.failure("설정 저장 형식 오류") }
        }
        var value: Any {
            switch self {
            case .text(let v): return v
            case .data(let v): return v
            case .date(let v): return v
            case .boolean(let v): return v
            case .integer(let v): return NSNumber(value: v)
            case .number(let v): return NSNumber(value: v)
            case .array(let v): return v.map(\.value)
            case .object(let v): return v.mapValues(\.value)
            }
        }
    }
    static func encodePreference(_ value: Any) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return "json:" + String(decoding: try encoder.encode(PreferenceValue(value)), as: UTF8.self)
    }
    static func decodePreference(_ text: String) throws -> Any {
        if text.hasPrefix("json:") {
            return try JSONDecoder().decode(PreferenceValue.self, from: Data(text.dropFirst(5).utf8)).value
        }
        if text.hasPrefix("plist:"), let data = Data(base64Encoded: String(text.dropFirst(6))),
           let root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any], let value = root["value"] {
            return value
        }
        return try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
    }

    static func capture(settings: Object) throws -> Snapshot {
        var result = Snapshot()
        for item in credentials {
            var q = item.query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
            var value: CFTypeRef?
            let code = SecItemCopyMatching(q as CFDictionary, &value)
            if code == errSecItemNotFound { continue }
            guard code == errSecSuccess, let data = value as? Data,
                  let text = String(data: data, encoding: .utf8) else { throw failure("기기 잠금 해제 후 다시 동기화하세요.") }
            if !text.isEmpty { result.entries["key." + item.id] = text }
        }
        for (name, value) in UserDefaults.standard.dictionaryRepresentation() where allowedPreference(name) {
            if let text = value as? String, text.isEmpty { continue }
            if name == "typecastApiKeys", let keys = value as? [String], keys.allSatisfy({ $0.isEmpty }) { continue }
            result.entries["pref." + name] = try encodePreference(value)
        }
        for (name, value) in settings {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
            result.entries["setting." + name] = String(decoding: data, as: UTF8.self)
        }
        return result
    }

    static func apply(_ snapshot: Snapshot, settings: (Object) throws -> Void) throws {
        guard snapshot.version == 1 else { throw failure("새 버전 앱이 필요한 설정 백업입니다.") }
        // Validate every structured value before writing any setting or credential.
        var decoded: [String: Any] = [:]
        for (key, text) in snapshot.entries where key.hasPrefix("pref.") {
            let name = String(key.dropFirst(5))
            guard allowedPreference(name) else { continue }
            let value = try decodePreference(text)
            guard validPreference(name, value) else { throw failure("설정 백업 형식을 확인하세요.") }
            decoded[name] = value
        }
        var vehicle: Object = [:]
        for (name, text) in snapshot.entries where name.hasPrefix("setting.") {
            vehicle[String(name.dropFirst(8))] = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        }
        for item in credentials {
            guard let text = snapshot.entries["key." + item.id], !text.isEmpty else { continue }
            guard text.utf8.count <= 16384 else { throw failure("키 백업 형식 오류") }
        }
        for item in credentials {
            guard let text = snapshot.entries["key." + item.id], !text.isEmpty else {
                let code = SecItemDelete(item.query as CFDictionary)
                guard code == errSecSuccess || code == errSecItemNotFound else { throw failure("키 변경 반영 실패 · 다시 동기화하세요.") }
                continue
            }
            let attrs: [String: Any] = [kSecValueData as String: Data(text.utf8), kSecAttrAccessible as String: item.accessibility]
            var code = SecItemUpdate(item.query as CFDictionary, attrs as CFDictionary)
            if code == errSecItemNotFound {
                var q = item.query; attrs.forEach { q[$0.key] = $0.value }
                code = SecItemAdd(q as CFDictionary, nil)
            }
            guard code == errSecSuccess else { throw failure("키 보안 저장 실패 · 다시 동기화하세요.") }
        }
        for name in UserDefaults.standard.dictionaryRepresentation().keys where allowedPreference(name) && decoded[name] == nil {
            UserDefaults.standard.removeObject(forKey: name)
        }
        decoded.forEach { UserDefaults.standard.set($0.value, forKey: $0.key) }
        if !vehicle.isEmpty { try settings(vehicle) }
        // These clients cache their setup while the app is running. Refresh without API requests.
        if let keys = decoded["typecastApiKeys"] as? [String], !keys.isEmpty {
            TypecastClient.shared.apiKeys = keys
            TypecastClient.shared.activeKeyIndex = min(max(0, (decoded["typecastActiveKeyIndex"] as? Int) ?? 0), keys.count - 1)
        } else { TypecastClient.shared.apiKeys = [""]; TypecastClient.shared.activeKeyIndex = 0 }
        TypecastClient.shared.selectedVoiceId = decoded["typecastVoiceId"] as? String ?? TypecastClient.defaultVoiceId
        TypecastClient.shared.isEnabled = decoded["typecastEnabled"] as? Bool ?? true
    }
    private static func validPreference(_ name: String, _ value: Any) -> Bool {
        if name == "typecastApiKeys" { return (value as? [String]).map { !$0.isEmpty && $0.count <= 50 && $0.allSatisfy { $0.utf8.count <= 16384 } } ?? false }
        if name == "typecastActiveKeyIndex" { return value is Int }
        if name == "typecastEnabled" { return value is Bool }
        return PropertyListSerialization.propertyList(["value": value], isValidFor: .binary)
    }
    private static let baselineMarker = "__baseline.hmac.v1"
    private static func fingerprint(_ name: String, _ value: String, token: String) -> String {
        Data(HMAC<SHA256>.authenticationCode(for: Data((name + "\0" + value).utf8), using: key(token: token, purpose: "comparison"))).base64EncodedString()
    }
    static func makeBaseline(_ snapshot: Snapshot, token: String) -> Snapshot {
        var result = Snapshot()
        for (name, value) in snapshot.entries { result.entries[name] = fingerprint(name, value, token: token) }
        result.entries[baselineMarker] = "1"
        return result
    }
    private static func differs(_ name: String, local: Snapshot, baseline: Snapshot, token: String?) -> Bool {
        if baseline.entries[baselineMarker] == "1", let token {
            return local.entries[name].map { fingerprint(name, $0, token: token) } != baseline.entries[name]
        }
        return local.entries[name] != baseline.entries[name]
    }
    static func hasChanges(_ local: Snapshot, baseline: Snapshot?, token: String) -> Bool {
        guard let baseline else { return true }
        return Set(local.entries.keys).union(baseline.entries.keys).filter { $0 != baselineMarker }.contains {
            differs($0, local: local, baseline: baseline, token: token)
        }
    }
    static func merge(local: Snapshot, remote: Snapshot, baseline: Snapshot?, baselineToken: String? = nil) -> Snapshot {
        var result = remote
        // A fresh installation cannot erase NAS values. After a baseline exists, explicit
        // edits and removals propagate; unchanged local values follow the latest NAS state.
        if let baseline {
            if baseline.entries[baselineMarker] == "1" && baselineToken == nil { return remote }
            for key in Set(local.entries.keys).union(baseline.entries.keys) where key != baselineMarker && differs(key, local: local, baseline: baseline, token: baselineToken) {
                result.entries[key] = local.entries[key]
            }
        } else {
            for (key, value) in local.entries where remote.entries[key] == nil { result.entries[key] = value }
        }
        return result
    }
    private static func key(token: String, purpose: String = "configuration") -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(token.utf8)),
                              salt: Data("YLCompanion.NAS.vault.v1".utf8), info: Data(purpose.utf8), outputByteCount: 32)
    }
    static func seal(_ snapshot: Snapshot, token: String) throws -> String {
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= 20_000_000, let sealed = try AES.GCM.seal(data, using: key(token: token), authenticating: Data("vault.v1".utf8)).combined else { throw failure("설정 백업 크기 초과") }
        return sealed.base64EncodedString()
    }
    static func open(_ sealed: String, token: String) throws -> Snapshot {
        guard let data = Data(base64Encoded: sealed), data.count <= 20_000_028 else { throw failure("설정 백업 형식 오류") }
        do {
            let raw = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key(token: token), authenticating: Data("vault.v1".utf8))
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: raw)
            guard snapshot.version == 1 else { throw failure("새 버전 앱이 필요합니다.") }
            return snapshot
        } catch { throw failure("설정 백업 암호 확인 실패 · NAS 연결 키와 백업을 확인하세요.") }
    }
    static func failure(_ text: String) -> NSError { NSError(domain: "NASConfigurationVault", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
