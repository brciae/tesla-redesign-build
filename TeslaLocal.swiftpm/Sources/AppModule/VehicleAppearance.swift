import Foundation

// Display approximations, not measured paint formulae. Names/codes follow Tesla's
// 2025+ Model Y / Model Y L service manual; original vehicle data is not inferred.
struct VehiclePaintPreset: Identifiable {
    let id: String
    let name: String
    let hex: String
    static let modelYL: [Self] = [
        .init(id: "PM00", name: "펄 화이트 프로", hex: "F0F0EC"),
        .init(id: "PX02", name: "다이아몬드 블랙", hex: "17191B"),
        .init(id: "PN01", name: "스텔스 그레이", hex: "41474C"),
        .init(id: "PN03", name: "코스믹 실버", hex: "A4A8AC"),
        .init(id: "PB01", name: "글레이셔 블루", hex: "7998B4"),
        .init(id: "PR01", name: "울트라 레드", hex: "A61924")
    ]
}

struct VehicleInteriorPreset: Identifiable {
    let id: String
    let name: String
    let hex: String
    let desc: String
    static let presets: [Self] = [
        .init(id: "INT01", name: "올 블랙", hex: "17191B", desc: "순정 다크 블랙 가죽 & 에보니 트림"),
        .init(id: "INT02", name: "블랙 & 화이트", hex: "EAEAEA", desc: "프리미엄 퓨어 화이트 비건 레더"),
        .init(id: "INT03", name: "새들 브라운", hex: "8B5A2B", desc: "고급스러운 탄 새들 가죽 톤"),
        .init(id: "INT04", name: "크림 베이지", hex: "DFD2BE", desc: "따뜻하고 아늑한 크림 베이지 톤"),
        .init(id: "INT05", name: "스포츠 레드", hex: "942020", desc: "다이내믹 퍼포먼스 레드 시트")
    ]
}

struct VehicleAppearance: Codable, Equatable {
    enum Finish: String, Codable, CaseIterable { case gloss = "유광", satin = "새틴", matte = "무광" }
    enum Wrap: String, Codable, CaseIterable { case none = "없음", stripes = "스트라이프", twoTone = "투톤", image = "이미지" }
    var enabled = false
    var paint = "334150"
    var finish: Finish = .gloss
    var tint = "101820"
    var tintStrength = 0.65
    var plate = ""
    var plateColor = "FFFFFF"
    var wrap: Wrap = .none
    var accent = "E4E5E7"
    var interiorColor = "17191B"
    // Only an app-created UUID filename, never a path from imports.
    var imageID: String? = nil
    static let original = Self()

    enum CodingKeys: String, CodingKey {
        case enabled, paint, finish, tint, tintStrength, plate, plateColor, wrap, accent, interiorColor, imageID
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        paint = try c.decodeIfPresent(String.self, forKey: .paint) ?? "334150"
        finish = try c.decodeIfPresent(Finish.self, forKey: .finish) ?? .gloss
        tint = try c.decodeIfPresent(String.self, forKey: .tint) ?? "101820"
        tintStrength = try c.decodeIfPresent(Double.self, forKey: .tintStrength) ?? 0.65
        plate = try c.decodeIfPresent(String.self, forKey: .plate) ?? ""
        plateColor = try c.decodeIfPresent(String.self, forKey: .plateColor) ?? "FFFFFF"
        wrap = try c.decodeIfPresent(Wrap.self, forKey: .wrap) ?? .none
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? "E4E5E7"
        interiorColor = try c.decodeIfPresent(String.self, forKey: .interiorColor) ?? "17191B"
        imageID = try c.decodeIfPresent(String.self, forKey: .imageID)
    }

    static func validHex(_ value: String) -> Bool {
        value.utf8.count == 6 && value.unicodeScalars.allSatisfy { (48...57).contains($0.value) || (65...70).contains($0.value) || (97...102).contains($0.value) }
    }
    func validated() -> Self {
        var value = self
        for key in [\Self.paint, \Self.tint, \Self.plateColor, \Self.accent, \Self.interiorColor] {
            if !Self.validHex(value[keyPath: key]) { value[keyPath: key] = Self.original[keyPath: key] }
            value[keyPath: key] = value[keyPath: key].uppercased()
        }
        value.tintStrength = tintStrength.isFinite ? min(1, max(0, tintStrength)) : 0.65
        value.plate = String(plate.filter { $0.isLetter || $0.isNumber || $0 == " " }.prefix(12))
        if let imageID, UUID(uuidString: imageID) == nil { value.imageID = nil }
        if value.wrap == .image && value.imageID == nil { value.wrap = .none }
        return value
    }
}
