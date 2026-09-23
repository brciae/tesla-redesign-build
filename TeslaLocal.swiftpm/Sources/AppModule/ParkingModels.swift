import Foundation

/// Classification of parking location types across all environments (indoor, outdoor, structure, EV, roadside).
enum ParkingLocationType: String, Codable {
    case underground = "지하 주차장"
    case tower = "지상 주차타워"
    case outdoor = "야외/노상 주차장"
    case evCharging = "전기차 충전구역"
    case general = "주차 구역"

    var badgeColorHex: String {
        switch self {
        case .underground: return "#10B981" // Emerald Green
        case .tower: return "#6366F1"       // Indigo
        case .outdoor: return "#06B6D4"     // Cyan
        case .evCharging: return "#3B82F6"  // Blue
        case .general: return "#8B5CF6"     // Purple
        }
    }

    var iconName: String {
        switch self {
        case .underground: return "arrow.down.circle.fill"
        case .tower: return "building.fill"
        case .outdoor: return "sun.max.fill"
        case .evCharging: return "bolt.car.fill"
        case .general: return "parkingsign.circle.fill"
        }
    }
}

/// Detailed vehicle telemetry captured at the moment of parking (from Tesla BLE / Fleet API)
struct VehicleParkingSnapshot: Codable, Equatable {
    var gear: String?
    var heading: Double?               // 0~360 degrees
    var headingDescription: String?    // e.g. "북서 (NW) 315°"
    var odometerKm: Double?
    var soc: Double?
    var rangeKm: Double?
    var isLocked: Bool?
    var areDoorsClosed: Bool?
    var isTrunkClosed: Bool?
    var isFrunkClosed: Bool?
    var isCharging: Bool?
    var chargerKW: Double?
    var minutesToLimit: Int?
    var addedKWh: Double?
    var insideTempC: Double?
    var outsideTempC: Double?
    var vehicleLatitude: Double?
    var vehicleLongitude: Double?
    var positionStatus: String?

    var securityText: String {
        if isLocked == false { return "차량 미잠금" }
        if areDoorsClosed == false || isTrunkClosed == false || isFrunkClosed == false { return "도어 또는 트렁크 열림" }
        if isLocked == true && areDoorsClosed == true && isTrunkClosed == true && isFrunkClosed == true { return "잠김 · 도어 닫힘" }
        return isLocked == true ? "잠김 · 도어 상태 미수신" : "잠금 상태 미수신"
    }

    var batteryText: String {
        guard let soc, soc.isFinite else { return "잔량 미수신" }
        var text = "\(Int(soc))%"
        if isCharging == true { text += " · 충전 중" }
        else if isCharging == false { text += " · 충전 안 함" }
        return text
    }
}

/// Detailed mobile sensor & vision analysis captured by iPhone
struct MobileParkingSnapshot: Codable, Equatable {
    var mobileLatitude: Double?
    var mobileLongitude: Double?
    var horizontalAccuracy: Double?
    var altitude: Double?
    var ocrFloor: String?
    var ocrPillar: String?
    var ocrSpecialZone: String?
    var rawOcrText: String?
    var buildingName: String?
    var address: String?
    var landmark: String?
    var photoFileName: String?
}

/// Cross-verification results between vehicle and mobile
struct ParkingCrossVerification: Codable, Equatable {
    var isLocationVerified: Bool = false
    var locationDistanceMeters: Double?
    var locationVerificationNote: String = ""
    var isSecurityVerified: Bool = false
    var securityWarning: String?
    var isBatteryVerified: Bool = false
    var overallStatus: String = "모바일 및 차량 종합 검증 완료"
}

/// Universal smart parking record combining both vehicle and mobile data
struct SmartParkingRecord: Identifiable, Codable, Equatable {
    var vehicleID: String? = nil
    var vehicleUpdatedAt: Date? = nil
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var locationType: ParkingLocationType = .general
    
    var vehicle: VehicleParkingSnapshot = VehicleParkingSnapshot()
    var mobile: MobileParkingSnapshot = MobileParkingSnapshot()
    var verification: ParkingCrossVerification = ParkingCrossVerification()

    mutating func refreshLocationType() {
        let photographedZone = mobile.ocrSpecialZone ?? ""
        if vehicle.isCharging == true || photographedZone.contains("전기차") || photographedZone.contains("충전") {
            locationType = .evCharging
        } else if locationType == .evCharging, vehicle.isCharging == false {
            locationType = .general
        }
    }

    // Primary display properties
    var displayTitle: String {
        var parts: [String] = []
        if let floor = mobile.ocrFloor { parts.append(floor) }
        if let pillar = mobile.ocrPillar { parts.append(pillar + " 기둥") }
        if let zone = mobile.ocrSpecialZone { parts.append(zone) }

        if !parts.isEmpty {
            return parts.joined(separator: " · ")
        }
        if let b = mobile.buildingName, !b.isEmpty { return b }
        if let l = mobile.landmark, !l.isEmpty { return l }
        if let a = mobile.address, !a.isEmpty { return a }
        return "주차 위치"
    }

    var displaySubtitle: String {
        var details: [String] = []
        if let b = mobile.buildingName, !b.isEmpty, !displayTitle.contains(b) {
            details.append(b)
        }
        if let a = mobile.address, !a.isEmpty {
            details.append(a)
        }
        return details.isEmpty ? locationType.rawValue : details.joined(separator: " · ")
    }

    var effectiveLatitude: Double? {
        vehicle.vehicleLatitude
    }

    var effectiveLongitude: Double? {
        vehicle.vehicleLongitude
    }
    func replacingPhotoMetadata(_ metadata: MobileParkingSnapshot) -> Self {
        var updated = self
        updated.mobile = metadata
        return updated
    }

    var briefingLines: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 H시 m분"
        return [displayTitle + ".", formatter.string(from: timestamp) + "에 저장한 위치입니다.",
                "마지막 수신 차량 상태는 \(vehicle.securityText), \(vehicle.batteryText)입니다."]
    }
}

enum ParkingWritePolicy {
    static func canComplete(revision: Int, currentRevision: Int, vin: String, selectedVIN: String) -> Bool {
        revision == currentRevision && !vin.isEmpty && vin == selectedVIN
    }
    static func canAttachPhoto(recordVIN: String?, selectedVIN: String) -> Bool {
        recordVIN == nil || (!selectedVIN.isEmpty && recordVIN == selectedVIN)
    }
}

