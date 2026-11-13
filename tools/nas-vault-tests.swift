import Foundation
import Security

typealias Object = [String: Any]
// No vendor client or external API is used by this executable.
final class TypecastClient {
    static let shared = TypecastClient()
    static let defaultVoiceId = "fixture"
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
        assert(NASConfigurationVault.merge(local: .init(), remote: saved, baseline: nil) == saved)
        assert(NASConfigurationVault.merge(local: .init(), remote: saved, baseline: saved).entries.isEmpty)
        assert(NASConfigurationVault.merge(local: saved, remote: .init(), baseline: saved).entries.isEmpty)
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
        for name in ["cost.gasoline", "navigation.home", "charging.favorites.v1", "appearance.v1.car", "vehicle.reference.car", "warranty.start.car", "navVoiceVolume", "unitDistance"] {
            assert(NASConfigurationVault.allowedPreference(name), "Missing entered setting: " + name)
        }
        for name in ["embeddedNavigationConsent", "automationSpeech.aiEnabled", "fleet.archive.address", "fleet.archive.cursor.car", "manualControlPending", "navigation.activeRecovery.v1"] {
            assert(!NASConfigurationVault.allowedPreference(name), "Device state or permission must not be restored: " + name)
        }
        let address: [String: Any] = ["name": "집", "latitude": 37.0, "longitude": 127.0]
        let addressData = try JSONSerialization.data(withJSONObject: address)
        let restoredAddress = try NASConfigurationVault.decodePreference(NASConfigurationVault.encodePreference(addressData)) as! Data
        assert(restoredAddress == addressData)
        let warranty = Date(timeIntervalSince1970: 1_750_000_000)
        let restoredWarranty = try NASConfigurationVault.decodePreference(NASConfigurationVault.encodePreference(warranty)) as! Date
        assert(restoredWarranty == warranty)
        let rate = try NASConfigurationVault.decodePreference(NASConfigurationVault.encodePreference(245.75)) as! Double
        assert(rate == 245.75)
        let firstOrder = try NASConfigurationVault.encodePreference(["tariff": 245.75, "radius": 150.0])
        let otherOrder = try NASConfigurationVault.encodePreference(["radius": 150.0, "tariff": 245.75])
        assert(firstOrder == otherOrder, "Equivalent settings must not look dirty")
        let compact = NASConfigurationVault.makeBaseline(saved, token: key)
        assert(!NASConfigurationVault.hasChanges(saved, baseline: compact, token: key))
        assert(NASConfigurationVault.hasChanges(changed, baseline: compact, token: key))
        assert(NASConfigurationVault.merge(local: changed, remote: saved, baseline: compact, baselineToken: key).entries["key.kakao"] == "changed")
        assert(NASConfigurationVault.merge(local: .init(), remote: saved, baseline: compact, baselineToken: key).entries.isEmpty)
        let large = NASConfigurationVault.Snapshot(entries: ["appearance.asset.fixture": String(repeating: "x", count: 2_000_000)])
        let largeBaseline = try JSONEncoder().encode(NASConfigurationVault.makeBaseline(large, token: key))
        assert(largeBaseline.count < 512)
        let baseSettings = NASConfigurationVault.Snapshot(entries: ["setting.tariff": "100", "setting.homePoint": "old-address"])
        let feeEdit = NASConfigurationVault.Snapshot(entries: ["setting.tariff": "200", "setting.homePoint": "old-address"])
        let addressEdit = NASConfigurationVault.Snapshot(entries: ["setting.tariff": "100", "setting.homePoint": "new-address"])
        let combined = NASConfigurationVault.merge(local: feeEdit, remote: addressEdit,
            baseline: NASConfigurationVault.makeBaseline(baseSettings, token: key), baselineToken: key)
        assert(combined.entries["setting.tariff"] == "200" && combined.entries["setting.homePoint"] == "new-address")
        assert(NASConfigurationVault.credentials.first { $0.id == "tesla.secret" }!.accessibility as String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        assert(NASConfigurationVault.credentials.first { $0.id == "kakao" }!.accessibility as String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        print("NAS vault merge, fresh install, multi-device, encryption and integrity tests passed")
    }
}
