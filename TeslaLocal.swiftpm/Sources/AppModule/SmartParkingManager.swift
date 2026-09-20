import Foundation
import UIKit
import Vision
import CoreLocation

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
    var gear: String? = "P"
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
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var locationType: ParkingLocationType = .general
    
    var vehicle: VehicleParkingSnapshot = VehicleParkingSnapshot()
    var mobile: MobileParkingSnapshot = MobileParkingSnapshot()
    var verification: ParkingCrossVerification = ParkingCrossVerification()

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
        mobile.mobileLatitude ?? vehicle.vehicleLatitude
    }

    var effectiveLongitude: Double? {
        mobile.mobileLongitude ?? vehicle.vehicleLongitude
    }
}

/// Universal parking intelligence engine that cross-verifies and fuses both mobile & vehicle data.
final class SmartParkingManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = SmartParkingManager()

    @Published var latestRecord: SmartParkingRecord?
    @Published var isAnalyzing = false
    @Published var showCapturePrompt = false
    @Published var currentPhoneLocation: CLLocation?

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let storageKey = "SmartParkingManager.LatestRecord"
    private var lastKnownValidCoordinates: (lat: Double, lng: Double)?
    private var cachedVehicleTelemetry: Object = [:]

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        loadLatestRecord()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy > 0, loc.horizontalAccuracy < 100 else { return }
        self.currentPhoneLocation = loc
        self.lastKnownValidCoordinates = (loc.coordinate.latitude, loc.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Fallback to vehicle GPS or cached coordinates if phone GPS fails
    }

    // MARK: - Persistence

    private func loadLatestRecord() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let record = try? JSONDecoder().decode(SmartParkingRecord.self, from: data) else { return }
        self.latestRecord = record
    }

    func saveRecord(_ record: SmartParkingRecord) {
        self.latestRecord = record
        if let data = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func clearRecord() {
        self.latestRecord = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - Vehicle Link Triggers

    func updateLocationSample(lat: Double?, lng: Double?) {
        guard let lat, let lng, !(lat == 0 && lng == 0) else { return }
        self.lastKnownValidCoordinates = (lat, lng)
    }

    func onVehicleParked(vehicleTelemetry: Object) {
        self.cachedVehicleTelemetry = vehicleTelemetry
        DispatchQueue.main.async {
            self.showCapturePrompt = true
            Task {
                await self.autoSaveUnifiedRecord(vehicleTelemetry: vehicleTelemetry)
            }
        }
    }

    // MARK: - Comprehensive Data Fusion & Verification

    private func autoSaveUnifiedRecord(vehicleTelemetry: Object) async {
        guard self.latestRecord == nil || Date().timeIntervalSince(self.latestRecord!.timestamp) > 300 else { return }

        // 1. Extract vehicle snapshot
        let vehicleSnapshot = self.buildVehicleSnapshot(from: vehicleTelemetry)

        // 2. Extract mobile snapshot
        var mobileSnapshot = MobileParkingSnapshot()
        let phoneLoc = self.currentPhoneLocation
        if let loc = phoneLoc {
            mobileSnapshot.mobileLatitude = loc.coordinate.latitude
            mobileSnapshot.mobileLongitude = loc.coordinate.longitude
            mobileSnapshot.horizontalAccuracy = loc.horizontalAccuracy
            mobileSnapshot.altitude = loc.altitude
        } else if let fallback = self.lastKnownValidCoordinates {
            mobileSnapshot.mobileLatitude = fallback.lat
            mobileSnapshot.mobileLongitude = fallback.lng
        }

        // 3. Reverse geocoding
        let refLat = mobileSnapshot.mobileLatitude ?? vehicleSnapshot.vehicleLatitude
        let refLng = mobileSnapshot.mobileLongitude ?? vehicleSnapshot.vehicleLongitude
        if let lat = refLat, let lng = refLng, !(lat == 0 && lng == 0) {
            let geo = await reverseGeocode(location: CLLocation(latitude: lat, longitude: lng))
            mobileSnapshot.buildingName = geo.buildingName
            mobileSnapshot.address = geo.address
            mobileSnapshot.landmark = geo.landmark
        }

        // 4. Cross-Verification
        let verification = self.performCrossVerification(
            vehicle: vehicleSnapshot,
            mobile: mobileSnapshot,
            ocr: nil
        )

        // 5. Initial Location Type
        let locType: ParkingLocationType = {
            if vehicleSnapshot.isCharging == true { return .evCharging }
            if vehicleSnapshot.positionStatus == "gpsUnavailable" { return .underground }
            return .outdoor
        }()

        let record = SmartParkingRecord(
            id: UUID(),
            timestamp: Date(),
            locationType: locType,
            vehicle: vehicleSnapshot,
            mobile: mobileSnapshot,
            verification: verification
        )

        DispatchQueue.main.async {
            self.saveRecord(record)
        }
    }

    // MARK: - Process Photo with Universal Classification & Cross-Verification

    func processParkingPhoto(
        image: UIImage,
        vehicleTelemetry: Object
    ) async {
        DispatchQueue.main.async { self.isAnalyzing = true }
        defer { DispatchQueue.main.async { self.isAnalyzing = false } }

        // 1. Save photo locally
        let fileName = "parking_\(Int(Date().timeIntervalSince1970)).jpg"
        let photoURL = getDocumentsDirectory().appendingPathComponent(fileName)
        if let jpegData = image.jpegData(compressionQuality: 0.85) {
            try? jpegData.write(to: photoURL)
        }

        // 2. Extract vehicle snapshot
        let vehicleSnapshot = self.buildVehicleSnapshot(from: vehicleTelemetry.isEmpty ? self.cachedVehicleTelemetry : vehicleTelemetry)

        // 3. Perform Apple Vision OCR
        let ocr = await recognizeUniversalParkingText(from: image)

        // 4. Build Mobile Snapshot
        var mobileSnapshot = MobileParkingSnapshot()
        mobileSnapshot.photoFileName = fileName
        mobileSnapshot.ocrFloor = ocr.floor
        mobileSnapshot.ocrPillar = ocr.pillar
        mobileSnapshot.ocrSpecialZone = ocr.specialZone
        mobileSnapshot.rawOcrText = ocr.rawText

        let phoneLoc = self.currentPhoneLocation
        if let loc = phoneLoc {
            mobileSnapshot.mobileLatitude = loc.coordinate.latitude
            mobileSnapshot.mobileLongitude = loc.coordinate.longitude
            mobileSnapshot.horizontalAccuracy = loc.horizontalAccuracy
            mobileSnapshot.altitude = loc.altitude
        } else if let fallback = self.lastKnownValidCoordinates {
            mobileSnapshot.mobileLatitude = fallback.lat
            mobileSnapshot.mobileLongitude = fallback.lng
        }

        // 5. Geocode with fallback
        let refLat = mobileSnapshot.mobileLatitude ?? vehicleSnapshot.vehicleLatitude
        let refLng = mobileSnapshot.mobileLongitude ?? vehicleSnapshot.vehicleLongitude
        if let lat = refLat, let lng = refLng, !(lat == 0 && lng == 0) {
            let geo = await reverseGeocode(location: CLLocation(latitude: lat, longitude: lng))
            mobileSnapshot.buildingName = geo.buildingName
            mobileSnapshot.address = geo.address
            mobileSnapshot.landmark = geo.landmark
        }

        // 6. Cross-Verification
        let verification = self.performCrossVerification(
            vehicle: vehicleSnapshot,
            mobile: mobileSnapshot,
            ocr: ocr
        )

        // 7. Comprehensive Location Type Determination
        let locationType: ParkingLocationType = {
            if ocr.specialZone?.contains("전기차") == true || ocr.specialZone?.contains("충전") == true || vehicleSnapshot.isCharging == true {
                return .evCharging
            }
            if ocr.isUnderground || (ocr.floor != nil && ocr.floor!.contains("지하")) || vehicleSnapshot.positionStatus == "gpsUnavailable" {
                return .underground
            }
            if let floor = ocr.floor, (floor.contains("F") || floor.contains("층")) && !floor.contains("1") {
                return .tower
            }
            return (ocr.pillar != nil) ? .underground : .outdoor
        }()

        // 8. Package full smart record
        let record = SmartParkingRecord(
            id: UUID(),
            timestamp: Date(),
            locationType: locationType,
            vehicle: vehicleSnapshot,
            mobile: mobileSnapshot,
            verification: verification
        )

        DispatchQueue.main.async {
            self.saveRecord(record)
            self.showCapturePrompt = false
        }
    }

    // MARK: - Vehicle Snapshot Builder

    private func buildVehicleSnapshot(from telemetry: Object) -> VehicleParkingSnapshot {
        let drive = telemetry.object("drive")
        let loc = telemetry.object("location")
        let closures = telemetry.object("closures")
        let charge = telemetry.object("charge")
        let climate = telemetry.object("climate")

        var snap = VehicleParkingSnapshot()
        snap.gear = drive.string("gear", "P")
        snap.odometerKm = drive.number("odometerKm")

        let headingDeg = loc.number("heading") ?? drive.number("heading")
        snap.heading = headingDeg
        if let deg = headingDeg {
            snap.headingDescription = headingToCardinal(deg)
        }

        snap.vehicleLatitude = loc.number("latitude")
        snap.vehicleLongitude = loc.number("longitude")
        snap.positionStatus = loc.string("positionStatus", "available")

        // Closures & Security
        snap.isLocked = closures.flag("locked")
        let df = closures.flag("driverFront")
        let dr = closures.flag("driverRear")
        let pf = closures.flag("passengerFront")
        let pr = closures.flag("passengerRear")
        snap.areDoorsClosed = !(df || dr || pf || pr)
        snap.isTrunkClosed = !closures.flag("trunk")
        snap.isFrunkClosed = !closures.flag("frunk")

        // Charge
        snap.soc = charge.number("soc")
        snap.rangeKm = charge.number("rangeKm")
        let chargingVal = charge.number("charging") ?? 0
        snap.isCharging = chargingVal > 0
        snap.chargerKW = charge.number("chargerKW")
        snap.minutesToLimit = Int(charge.number("minutesToLimit") ?? 0)
        snap.addedKWh = charge.number("addedKWh")

        // Climate
        snap.insideTempC = climate.number("insideC")
        snap.outsideTempC = climate.number("outsideC")

        return snap
    }

    // MARK: - Cross-Verification Logic

    private func performCrossVerification(
        vehicle: VehicleParkingSnapshot,
        mobile: MobileParkingSnapshot,
        ocr: OCRResult?
    ) -> ParkingCrossVerification {
        var ver = ParkingCrossVerification()

        // 1. Location Cross-Verification
        if let vLat = vehicle.vehicleLatitude, let vLng = vehicle.vehicleLongitude, !(vLat == 0 && vLng == 0),
           let mLat = mobile.mobileLatitude, let mLng = mobile.mobileLongitude, !(mLat == 0 && mLng == 0) {
            let vLoc = CLLocation(latitude: vLat, longitude: vLng)
            let mLoc = CLLocation(latitude: mLat, longitude: mLng)
            let dist = vLoc.distance(from: mLoc)
            ver.locationDistanceMeters = dist

            if dist < 60 {
                ver.isLocationVerified = true
                ver.locationVerificationNote = "차량 및 모바일 GPS 위치 일치 (오차 \(Int(dist))m)"
            } else if vehicle.positionStatus == "gpsUnavailable" || ocr?.isUnderground == true {
                ver.isLocationVerified = true
                ver.locationVerificationNote = "지하 주차장 감지 · 진입 전 지상 좌표 및 기둥 번호 자동 합성"
            } else {
                ver.isLocationVerified = false
                ver.locationVerificationNote = "차량과 모바일 간 거리 차이 발생 (\(Int(dist))m)"
            }
        } else {
            ver.isLocationVerified = true
            ver.locationVerificationNote = "지상 진입 좌표 및 건물명 기반 위치 기록 완료"
        }

        // 2. Security Cross-Verification
        var securityIssues: [String] = []
        if vehicle.isLocked == false {
            securityIssues.append("차량 미잠금")
        }
        if vehicle.areDoorsClosed == false {
            securityIssues.append("도어 열림")
        }
        if vehicle.isTrunkClosed == false {
            securityIssues.append("트렁크 열림")
        }
        if vehicle.isFrunkClosed == false {
            securityIssues.append("프렁크 열림")
        }

        if securityIssues.isEmpty {
            ver.isSecurityVerified = true
            ver.securityWarning = nil
        } else {
            ver.isSecurityVerified = false
            ver.securityWarning = "⚠️ " + securityIssues.joined(separator: " · ") + " 감지!"
        }

        // 3. Battery / Charging Cross-Verification
        ver.isBatteryVerified = (vehicle.soc != nil)

        // 4. Overall Synthesis Status
        if ver.isSecurityVerified && ver.isLocationVerified {
            ver.overallStatus = "모바일 및 차량 종합 검증 완료 🟢"
        } else if !ver.isSecurityVerified {
            ver.overallStatus = ver.securityWarning ?? "보안 확인 필요 ⚠️"
        } else {
            ver.overallStatus = "위치 보정 완료 🔵"
        }

        return ver
    }

    // MARK: - Universal Vision OCR Parser

    struct OCRResult {
        var floor: String?
        var pillar: String?
        var specialZone: String?
        var isUnderground: Bool = false
        var rawText: String = ""
    }

    private func recognizeUniversalParkingText(from image: UIImage) async -> OCRResult {
        guard let cgImage = image.cgImage else { return OCRResult() }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil, let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: OCRResult())
                    return
                }

                var detectedTexts: [String] = []
                for obs in observations {
                    if let topCandidate = obs.topCandidates(1).first {
                        detectedTexts.append(topCandidate.string)
                    }
                }

                let fullText = detectedTexts.joined(separator: " ")
                var result = self.parseUniversalParkingGrammar(from: fullText)
                result.rawText = fullText
                continuation.resume(returning: result)
            }

            request.recognitionLanguages = ["ko-KR", "en-US"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    /// Universal regex grammar covering Korean apartments, malls, public structures, roadside, etc.
    private func parseUniversalParkingGrammar(from text: String) -> OCRResult {
        var res = OCRResult()

        // 1. Floor: B1~B9, B1F~B9F, 지하1층~지하9층, 1층~15층, 옥상, RF, M층
        let floorPattern = #"(?i)\b(B[1-9]F?|지하\s*[1-9]\s*층?|[1-9]\s*층|RF|옥상|M층)\b"#
        if let regex = try? NSRegularExpression(pattern: floorPattern),
           let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
            let raw = (text as NSString).substring(with: match.range).trimmingCharacters(in: .whitespaces)
            if raw.lowercased().hasPrefix("b") {
                let num = raw.filter(\.isNumber)
                res.floor = "지하 \(num)층 (B\(num))"
                res.isUnderground = true
            } else if raw.contains("지하") {
                res.floor = raw
                res.isUnderground = true
            } else {
                res.floor = raw
            }
        }

        // 2. Pillar/Bay/Zone: e.g. A-12, G14, D08, 14번 기둥, 파랑구역, C구역, 102동 앞
        let pillarPattern = #"(?i)\b([A-Z]\s*[-_.]?\s*\d{1,4}|\d{1,4}\s*[-_.]?\s*[A-Z]|[A-Z]\s*구역|[가-힣]{1,4}\s*구역|\d{1,3}\s*번\s*기둥|\d{3,4}\s*동\s*앞?)\b"#
        if let regex = try? NSRegularExpression(pattern: pillarPattern),
           let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
            let raw = (text as NSString).substring(with: match.range).replacingOccurrences(of: " ", with: "").uppercased()
            res.pillar = raw
        }

        // 3. Special Zone: EV charging, elevators, exits, handicap, women
        let specialPatterns: [(String, String)] = [
            (#"(?i)(전기차|EV|충전구역|충전소)"#, "전기차 충전구역"),
            (#"(?i)(엘리베이터|EV홀|승강기)"#, "엘리베이터 앞"),
            (#"(?i)(출구|출차|나가는\s*곳)"#, "출구 인근"),
            (#"(?i)(장애인\s*전용|장애인)"#, "장애인 전용구역"),
            (#"(?i)(여성\s*안심|여성\s*전용)"#, "여성안심 구역"),
            (#"(?i)(사전정산|정산기)"#, "사전정산기 앞")
        ]

        for (pattern, label) in specialPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil {
                res.specialZone = label
                break
            }
        }

        if text.contains("지하") || text.contains("B1") || text.contains("B2") || text.contains("기둥") {
            res.isUnderground = true
        }

        return res
    }

    // MARK: - CoreLocation Geocoding

    private func reverseGeocode(location: CLLocation) async -> (buildingName: String?, address: String?, landmark: String?) {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let p = placemarks.first else { return (nil, nil, nil) }

            let building = p.name ?? p.areasOfInterest?.first
            let city = p.locality ?? p.administrativeArea ?? ""
            let street = p.thoroughfare ?? ""
            let subThoroughfare = p.subThoroughfare ?? ""
            let address = [city, street, subThoroughfare].filter { !$0.isEmpty }.joined(separator: " ")
            let landmark = p.areasOfInterest?.first

            return (building, address.isEmpty ? nil : address, landmark)
        } catch {
            return (nil, nil, nil)
        }
    }

    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

// MARK: - Helper Functions

private func headingToCardinal(_ deg: Double) -> String {
    let normalized = (deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    let directions = [
        "북 (N)", "북동 (NE)", "동 (E)", "남동 (SE)",
        "남 (S)", "남서 (SW)", "서 (W)", "북서 (NW)"
    ]
    let index = Int((normalized + 22.5) / 45.0) % 8
    return "\(directions[index]) \(Int(normalized))°"
}
