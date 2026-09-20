import SwiftUI
import CryptoKit
import ImageIO

@MainActor
final class VehicleAppearanceStore: ObservableObject {
    static let shared = VehicleAppearanceStore()
    @Published private(set) var revision = 0
    private let defaults: UserDefaults
    private let folder: URL
    init(defaults: UserDefaults = .standard, folder: URL? = nil) {
        self.defaults = defaults
        self.folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("YLCompanion/Appearance", isDirectory: true)
    }
    static func vehicleKey(vin: String, demo: Bool) -> String {
        let clean = vin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if demo { return "demo" }
        if clean.isEmpty { return "unassigned" }
        return SHA256.hash(data: Data(clean.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func value(for key: String) -> VehicleAppearance {
        guard let data = defaults.data(forKey: "appearance.v1." + key), let value = try? JSONDecoder().decode(VehicleAppearance.self, from: data) else { return .original }
        return value.validated()
    }
    func save(_ value: VehicleAppearance, for key: String) throws {
        defaults.set(try JSONEncoder().encode(value.validated()), forKey: "appearance.v1." + key)
        revision += 1
    }
    func imageURL(_ id: String?) -> URL? {
        guard let id, UUID(uuidString: id) != nil else { return nil }
        return folder.appendingPathComponent(id + ".png")
    }
    // Downsample before decoding a full camera image; no metadata/location retained.
    func importImage(_ data: Data) throws -> String {
        guard data.count <= 12_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1024, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary),
              let png = UIImage(cgImage: cg).pngData() else { throw LocalError.message("12 MB 이하의 PNG·JPEG 이미지가 필요함") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = UUID().uuidString
        try png.write(to: imageURL(id)!, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return id
    }
    func discardUncommitted(_ ids: Set<String>, keeping: String?) {
        // This editor owns only these new images; never delete another vehicle's file.
        for id in ids where id != keeping { if let url = imageURL(id) { try? FileManager.default.removeItem(at: url) } }
    }
}

extension UIColor {
    convenience init(appearanceHex: String) {
        let number = UInt32(appearanceHex, radix: 16) ?? 0x334150
        self.init(red: CGFloat((number >> 16) & 255)/255, green: CGFloat((number >> 8) & 255)/255, blue: CGFloat(number & 255)/255, alpha: 1)
    }
    var appearanceHex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(min(1,max(0,r))*255), Int(min(1,max(0,g))*255), Int(min(1,max(0,b))*255))
    }
}
