import Foundation

typealias Object = [String: Any]
// No vendor client or external API is used by this executable.
final class TypecastClient {
    static let shared = TypecastClient()
    var apiKeys: [String] = []
    var activeKeyIndex = 0
    var selectedVoiceId = ""
    var isEnabled = false
}
@main struct NASVaultTests {
    static func main() throws {
        let key = String(repeating: "fixture-only-not-a-real-key-", count: 3)
        let saved = NASConfigurationVault.Snapshot(entries: ["key.kakao": "fixture", "pref.spotify.clientID": "\"saved\""])
        let fresh = NASConfigurationVault.Snapshot(entries: ["pref.spotify.clientID": "\"default\""])
        assert(NASConfigurationVault.merge(local: fresh, remote: saved, baseline: nil) == saved)
        let changed = NASConfigurationVault.Snapshot(entries: ["key.kakao": "changed"])
        assert(NASConfigurationVault.merge(local: changed, remote: saved, baseline: saved).entries["key.kakao"] == "changed")
        assert(NASConfigurationVault.merge(local: .init(), remote: saved, baseline: saved) == saved)
        let anotherDevice = NASConfigurationVault.Snapshot(entries: ["key.kakao": "new-remote"])
        assert(NASConfigurationVault.merge(local: saved, remote: anotherDevice, baseline: saved).entries["key.kakao"] == "new-remote")
        let sealed = try NASConfigurationVault.seal(saved, token: key)
        let opened = try NASConfigurationVault.open(sealed, token: key)
        let second = try NASConfigurationVault.seal(saved, token: key)
        assert(opened == saved)
        assert(sealed != second, "Fresh nonce required")
        do { _ = try NASConfigurationVault.open(sealed, token: "wrong"); fatalError("Wrong key accepted") } catch {}
        var tampered = Data(base64Encoded: sealed)!
        tampered[tampered.count - 1] ^= 1
        do { _ = try NASConfigurationVault.open(tampered.base64EncodedString(), token: key); fatalError("Tampering accepted") } catch {}
        assert(!NASConfigurationVault.credentials.contains { $0.id.contains("refresh") || $0.id.contains("access") || $0.id.contains("BLE") })
        print("NAS vault merge, fresh install, multi-device, encryption and integrity tests passed")
    }
}
