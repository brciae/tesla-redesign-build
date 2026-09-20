import Foundation
import JavaScriptCore
import CryptoKit
import Security

typealias Object = [String: Any]
extension Dictionary where Key == String, Value == Any {
    func object(_ key: String) -> Object { self[key] as? Object ?? [:] }
    func rows(_ key: String) -> [Object] { self[key] as? [Object] ?? [] }
    func string(_ key: String, _ fallback: String = "") -> String { self[key] as? String ?? fallback }
    func number(_ key: String) -> Double? { (self[key] as? NSNumber)?.doubleValue }
    func flag(_ key: String) -> Bool { self[key] as? Bool ?? false }
}
enum LocalError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}
extension Data {
    var hexadecimal: String { map { String(format: "%02x", $0) }.joined() }
    init(hex: String) throws {
        guard hex.count % 2 == 0, hex.count <= 262144 else { throw LocalError.message("16진수 길이 오류") }
        var result = Data(); var cursor = hex.startIndex
        while cursor < hex.endIndex {
            let end = hex.index(cursor, offsetBy: 2)
            guard let byte = UInt8(hex[cursor..<end], radix: 16) else { throw LocalError.message("16진수 형식 오류") }
            result.append(byte); cursor = end
        }
        self = result
    }
}
func encodeJSON(_ value: Any) throws -> String {
    String(data: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]), encoding: .utf8)!
}
func decodeJSON(_ value: String) throws -> Any {
    try JSONSerialization.jsonObject(with: Data(value.utf8), options: [.fragmentsAllowed])
}

final class CryptoService {
    private let service: String
    private var vin = ""
    private var privateKey: P256.KeyAgreement.PrivateKey?
    init(service: String = "YLCompanion.BLE.P256") { self.service = service }
    func configure(_ vin: String) { self.vin = vin; privateKey = nil }
    private func key() throws -> P256.KeyAgreement.PrivateKey {
        if let key = privateKey { return key }
        guard vin.count == 17 else { throw LocalError.message("VIN 설정 필요") }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: vin]
        var lookup = query; lookup[kSecReturnData as String] = true; lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            let key = try P256.KeyAgreement.PrivateKey(rawRepresentation: data); privateKey = key; return key
        }
        guard status == errSecItemNotFound else { throw LocalError.message("보안 키 읽기 실패: \(status)") }
        let key = P256.KeyAgreement.PrivateKey()
        var insert = query; insert[kSecValueData as String] = key.rawRepresentation
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let result = SecItemAdd(insert as CFDictionary, nil)
        guard result == errSecSuccess else { throw LocalError.message("보안 키 저장 실패: \(result)") }
        privateKey = key; return key
    }
    func perform(_ operation: String, _ payload: String) -> String {
        do {
            let a = try decodeJSON(payload) as? Object ?? [:]
            func data(_ name: String) throws -> Data { try Data(hex: a.string(name)) }
            let value: Any
            switch operation {
            case "random":
                let count = Int(a.number("count") ?? 0)
                guard (1...64).contains(count) else { throw LocalError.message("난수 길이 오류") }
                var buffer = [UInt8](repeating: 0, count: count)
                guard SecRandomCopyBytes(kSecRandomDefault, count, &buffer) == errSecSuccess else { throw LocalError.message("난수 생성 실패") }
                value = Data(buffer).hexadecimal
            case "publicKey": value = try key().publicKey.x963Representation.hexadecimal
            case "derive":
                let peer = try P256.KeyAgreement.PublicKey(x963Representation: data("publicKey"))
                let secret = try key().sharedSecretFromKeyAgreement(with: peer)
                value = secret.withUnsafeBytes { Data(Insecure.SHA1.hash(data: Data($0))).prefix(16).hexadecimal }
            case "sha1": value = try Data(Insecure.SHA1.hash(data: data("data"))).hexadecimal
            case "sha256": value = try Data(SHA256.hash(data: data("data"))).hexadecimal
            case "hmac": value = try Data(HMAC<SHA256>.authenticationCode(for: data("data"), using: SymmetricKey(data: data("key")))).hexadecimal
            case "hmacValid": value = try HMAC<SHA256>.isValidAuthenticationCode(data("tag"), authenticating: data("data"), using: SymmetricKey(data: data("key")))
            case "seal":
                let sealed = try AES.GCM.seal(data("plain"), using: SymmetricKey(data: data("key")), nonce: AES.GCM.Nonce(data: data("nonce")), authenticating: data("aad"))
                value = ["cipher": sealed.ciphertext.hexadecimal, "tag": sealed.tag.hexadecimal]
            case "open":
                let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: data("nonce")), ciphertext: data("cipher"), tag: data("tag"))
                value = try AES.GCM.open(box, using: SymmetricKey(data: data("key")), authenticating: data("aad")).hexadecimal
            default: throw LocalError.message("허용되지 않는 암호 작업")
            }
            return try encodeJSON(["ok": true, "value": value])
        } catch { return (try? encodeJSON(["ok": false, "error": error.localizedDescription])) ?? "{\"ok\":false}" }
    }
}

final class LocalRuntime {
    let crypto = CryptoService()
    let controlCrypto = CryptoService(service: "YLCompanion.BLE.P256.Control")
    private let context: JSContext
    init() throws {
        guard let context = JSContext() else { throw LocalError.message("분석 엔진 생성 실패") }
        self.context = context
        let bridge: @convention(block) (String, String) -> String = { [crypto = self.crypto] op, body in crypto.perform(op, body) }
        context.setObject(bridge, forKeyedSubscript: "nativeCrypto" as NSString)
        let controlBridge: @convention(block) (String, String) -> String = { [crypto = self.controlCrypto] op, body in crypto.perform(op, body) }
        context.setObject(controlBridge, forKeyedSubscript: "nativeControlCrypto" as NSString)
        for name in ["protocol", "analysis", "vehicle3d", "home", "bridge"] {
            context.evaluateScript(try EmbeddedAppResources.text(named: "\(name).js"))
            if let error = context.exception { throw LocalError.message(error.toString()) }
        }
    }
    func call(_ operation: String, _ argument: Any = [:]) throws -> Any {
        context.exception = nil
        let result = context.objectForKeyedSubscript("hostCall")?.call(withArguments: [operation, try encodeJSON(argument)])
        if let error = context.exception { throw LocalError.message(error.toString()) }
        guard let json = result?.toString(), let response = try decodeJSON(json) as? Object else { throw LocalError.message("분석 엔진 응답 오류") }
        guard response.flag("ok") else { throw LocalError.message(response.string("error", "알 수 없는 오류")) }
        return response["value"] ?? NSNull()
    }
}
