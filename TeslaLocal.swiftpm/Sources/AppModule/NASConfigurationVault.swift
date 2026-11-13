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
        var query: [String: Any] {
            var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account]
            if let service { q[kSecAttrService as String] = service }
            return q
        }
    }
    static let credentials: [Credential] = [
        .init(id: "tesla.clientID", service: nil, account: "TeslaFleetClient.ClientId"),
        .init(id: "tesla.redirect", service: nil, account: "TeslaFleetClient.RedirectUri"),
        .init(id: "tesla.secret", service: nil, account: "TeslaFleetClient.ClientSecret"),
        .init(id: "kakao", service: "YLCompanion.KakaoNavigation", account: "nativeAppKey"),
        .init(id: "charging", service: "YL.public.charging", account: "data.go.kr")
    ] + ["OpenAI", "Claude", "Gemini"].map { .init(id: "ai." + $0, service: "YL.automation.api", account: $0) }

    // Keep this allowlist separate from ordinary, unencrypted JSON exports.
    static let preferences = ["fleetCommandProxy", "spotify.clientID", "typecastApiKeys", "typecastActiveKeyIndex",
        "typecastVoiceId", "typecastEnabled", "cost.gasoline", "cost.gasolineEfficiency", "cost.electricity",
        "automationAPI.provider", "automationAPI.model"]

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
        for name in preferences {
            guard let value = UserDefaults.standard.object(forKey: name) else { continue }
            if let text = value as? String, text.isEmpty { continue }
            if name == "typecastApiKeys", let keys = value as? [String], keys.allSatisfy({ $0.isEmpty }) { continue }
            let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
            result.entries["pref." + name] = String(decoding: data, as: UTF8.self)
        }
        if !settings.isEmpty {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys])
            result.entries["vehicle.settings"] = String(decoding: data, as: UTF8.self)
        }
        return result
    }

    static func apply(_ snapshot: Snapshot, settings: (Object) throws -> Void) throws {
        guard snapshot.version == 1 else { throw failure("새 버전 앱이 필요한 설정 백업입니다.") }
        // Validate every structured value before writing any setting or credential.
        var decoded: [String: Any] = [:]
        for name in preferences {
            if let text = snapshot.entries["pref." + name] {
                let value = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
                guard validPreference(name, value) else { throw failure("설정 백업 형식을 확인하세요.") }
                decoded[name] = value
            }
        }
        var vehicle: Object?
        if let text = snapshot.entries["vehicle.settings"] {
            guard let value = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? Object else { throw failure("차량 설정 백업 형식 오류") }
            vehicle = value
        }
        for item in credentials {
            guard let text = snapshot.entries["key." + item.id], !text.isEmpty else { continue }
            guard text.utf8.count <= 16384 else { throw failure("키 백업 형식 오류") }
        }
        for item in credentials {
            guard let text = snapshot.entries["key." + item.id], !text.isEmpty else { continue }
            let attrs: [String: Any] = [kSecValueData as String: Data(text.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
            var code = SecItemUpdate(item.query as CFDictionary, attrs as CFDictionary)
            if code == errSecItemNotFound {
                var q = item.query; attrs.forEach { q[$0.key] = $0.value }
                code = SecItemAdd(q as CFDictionary, nil)
            }
            guard code == errSecSuccess else { throw failure("키 보안 저장 실패 · 다시 동기화하세요.") }
        }
        decoded.forEach { UserDefaults.standard.set($0.value, forKey: $0.key) }
        if let vehicle { try settings(vehicle) }
        // These clients cache their setup while the app is running. Refresh without API requests.
        if let keys = decoded["typecastApiKeys"] as? [String], !keys.isEmpty {
            TypecastClient.shared.apiKeys = keys
            TypecastClient.shared.activeKeyIndex = min(max(0, (decoded["typecastActiveKeyIndex"] as? Int) ?? 0), keys.count - 1)
        }
        if let voice = decoded["typecastVoiceId"] as? String { TypecastClient.shared.selectedVoiceId = voice }
        if let enabled = decoded["typecastEnabled"] as? Bool { TypecastClient.shared.isEnabled = enabled }
    }
    private static func validPreference(_ name: String, _ value: Any) -> Bool {
        if name == "typecastApiKeys" { return (value as? [String]).map { !$0.isEmpty && $0.count <= 50 && $0.allSatisfy { $0.utf8.count <= 16384 } } ?? false }
        if name == "typecastActiveKeyIndex" { return value is Int }
        if name == "typecastEnabled" { return value is Bool }
        return value is String
    }
    static func merge(local: Snapshot, remote: Snapshot, baseline: Snapshot?) -> Snapshot {
        var result = remote
        // First use: NAS wins. Later: only intentional local changes replace NAS values.
        // Absence never deletes a saved key; a newly installed phone cannot erase the vault.
        for (key, value) in local.entries where remote.entries[key] == nil || (baseline != nil && baseline?.entries[key] != value) {
            result.entries[key] = value
        }
        return result
    }
    private static func key(token: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(token.utf8)),
                              salt: Data("YLCompanion.NAS.vault.v1".utf8), info: Data("configuration".utf8), outputByteCount: 32)
    }
    static func seal(_ snapshot: Snapshot, token: String) throws -> String {
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= 250000, let sealed = try AES.GCM.seal(data, using: key(token: token), authenticating: Data("vault.v1".utf8)).combined else { throw failure("설정 백업 크기 초과") }
        return sealed.base64EncodedString()
    }
    static func open(_ sealed: String, token: String) throws -> Snapshot {
        guard let data = Data(base64Encoded: sealed), data.count <= 262144 else { throw failure("설정 백업 형식 오류") }
        do {
            let raw = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key(token: token), authenticating: Data("vault.v1".utf8))
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: raw)
            guard snapshot.version == 1 else { throw failure("새 버전 앱이 필요합니다.") }
            return snapshot
        } catch { throw failure("설정 백업 암호 확인 실패 · NAS 연결 키와 백업을 확인하세요.") }
    }
    static func failure(_ text: String) -> NSError { NSError(domain: "NASConfigurationVault", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
