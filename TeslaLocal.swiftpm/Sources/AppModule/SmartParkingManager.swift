import Foundation
import UIKit
import Vision
import CoreLocation

/// Universal parking intelligence engine that cross-verifies and fuses both mobile & vehicle data.
final class SmartParkingManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = SmartParkingManager()

    @Published var latestRecord: SmartParkingRecord?
    @Published var isAnalyzing = false
    @Published var showCapturePrompt = false
    @Published var currentPhoneLocation: CLLocation?
    @Published var fleetParkingStatus = "주차 상태 미수신"
    private var fleetSample: FleetVehicleSnapshot?
    private var recordRevision = 0
    var selectedVehicleID: String {
        if let model = AppModel.shared, model.link.authentic { return model.settings.string("vin") }
        let fleetVIN = TeslaFleetClient.shared.selectedVin
        return fleetVIN.isEmpty ? (AppModel.shared?.settings.string("vin") ?? "") : fleetVIN
    }

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
        guard let loc = locations.last, loc.horizontalAccuracy > 0, loc.horizontalAccuracy < 100,
              abs(loc.timestamp.timeIntervalSinceNow) <= 30 else { return }
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
        recordRevision += 1
        self.latestRecord = record
        if let data = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func clearRecord() {
        recordRevision += 1
        self.latestRecord = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - Vehicle Link Triggers

    func observeFleet(_ snapshot: FleetVehicleSnapshot) {
        fleetSample = snapshot
        guard let telemetry = snapshot.parkingTelemetry() else { fleetParkingStatus = "최근 차량 위치·기어 수신 필요"; return }
        let gear = telemetry.object("drive").string("gear")
        let charging = telemetry.object("charge")["isCharging"] as? Bool
        guard gear == "P" || charging == true else {
            fleetParkingStatus = ["D", "R", "N"].contains(gear) ? "주차 상태가 아님" : "차량 위치 수신 · 주차 여부는 직접 확인 필요"
            return
        }
        fleetParkingStatus = "차량 주차 상태 확인됨"
        saveFleetParking(snapshot, confirmed: false)
    }

    func saveCurrentFleetParking() {
        guard let snapshot = fleetSample, snapshot.vin == TeslaFleetClient.shared.selectedVin else { return }
        saveFleetParking(snapshot, confirmed: true)
    }

    func photoTelemetry(fallback: Object) -> Object {
        if let snapshot = fleetSample, snapshot.vin == TeslaFleetClient.shared.selectedVin,
           let telemetry = snapshot.parkingTelemetry() { return telemetry }
        return fallback
    }

    private func saveFleetParking(_ snapshot: FleetVehicleSnapshot, confirmed: Bool) {
        guard snapshot.vin == TeslaFleetClient.shared.selectedVin,
              let telemetry = snapshot.parkingTelemetry() else { return }
        let vehicle = buildVehicleSnapshot(from: telemetry)
        let drive = telemetry.object("drive")
        guard !["D", "R", "N"].contains(drive.string("gear")), (drive.number("speedKmh") ?? 0) <= 0 else { fleetParkingStatus = "주행 상태에서는 주차 위치를 저장할 수 없음"; return }
        guard let lat = vehicle.vehicleLatitude, let lon = vehicle.vehicleLongitude else { fleetParkingStatus = "차량 GPS 미수신 · 주차 위치 저장 대기"; return }
        let samePlace: Bool = {
            guard let old = latestRecord, old.vehicleID == snapshot.vin || (confirmed && old.vehicleID == nil),
                  let oldLat = old.vehicle.vehicleLatitude, let oldLon = old.vehicle.vehicleLongitude else { return false }
            return CLLocation(latitude: lat, longitude: lon).distance(from: CLLocation(latitude: oldLat, longitude: oldLon)) < 60
        }()
        if samePlace, var existing = latestRecord {
            existing.vehicleID = snapshot.vin
            existing.vehicleUpdatedAt = snapshot.receivedAt
            existing.vehicle = vehicle
            existing.verification = performCrossVerification(vehicle: vehicle, mobile: existing.mobile, ocr: nil)
            saveRecord(existing) // Preserve capture time, ID, photo, floor and pillar.
            fleetParkingStatus = "저장된 주차 위치의 차량 상태 갱신됨"
            return
        }
        guard latestRecord == nil || confirmed else { fleetParkingStatus = "다른 주차 위치 수신 · 새 위치 저장 확인 필요"; return }
        var record = SmartParkingRecord()
        record.vehicleID = snapshot.vin
        record.vehicleUpdatedAt = snapshot.receivedAt
        record.timestamp = snapshot.receivedAt // observation time, not inferred arrival time
        record.vehicle = vehicle
        record.locationType = vehicle.isCharging == true ? .evCharging : .general
        record.verification = performCrossVerification(vehicle: vehicle, mobile: record.mobile, ocr: nil)
        saveRecord(record)
        fleetParkingStatus = "차량 좌표로 주차 위치 저장됨"
        let identity = record.id
        Task {
            let geo = await reverseGeocode(location: CLLocation(latitude: lat, longitude: lon))
            await MainActor.run {
                guard var current = self.latestRecord, current.id == identity, current.vehicleID == snapshot.vin else { return }
                current.mobile.buildingName = geo.buildingName; current.mobile.address = geo.address; current.mobile.landmark = geo.landmark
                self.saveRecord(current)
            }
        }
    }

    func updateLocationSample(lat: Double?, lng: Double?) {
        guard let lat, let lng, !(lat == 0 && lng == 0) else { return }
        self.lastKnownValidCoordinates = (lat, lng)
    }

    func onVehicleParked(vehicleTelemetry: Object, newArrival: Bool = false, vin: String = "") {
        self.cachedVehicleTelemetry = vehicleTelemetry
        DispatchQueue.main.async {
            self.showCapturePrompt = true
            Task {
                await self.autoSaveUnifiedRecord(vehicleTelemetry: vehicleTelemetry, newArrival: newArrival, vin: vin)
            }
        }
    }

    // MARK: - Comprehensive Data Fusion & Verification

    @MainActor private func autoSaveUnifiedRecord(vehicleTelemetry: Object, newArrival: Bool, vin: String) async {
        let revision = recordRevision
        if !newArrival, latestRecord != nil { return }

        // 1. Extract vehicle snapshot
        let vehicleSnapshot = self.buildVehicleSnapshot(from: vehicleTelemetry)

        // 2. Extract mobile snapshot
        var mobileSnapshot = MobileParkingSnapshot()
        let phoneLoc = self.currentPhoneLocation
        if let loc = phoneLoc, abs(loc.timestamp.timeIntervalSinceNow) <= 30 {
            mobileSnapshot.mobileLatitude = loc.coordinate.latitude
            mobileSnapshot.mobileLongitude = loc.coordinate.longitude
            mobileSnapshot.horizontalAccuracy = loc.horizontalAccuracy
            mobileSnapshot.altitude = loc.altitude
        }

        // 3. Reverse geocoding
        let refLat = vehicleSnapshot.vehicleLatitude
        let refLng = vehicleSnapshot.vehicleLongitude
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

            return .general
        }()

        var record = SmartParkingRecord(
            id: UUID(),
            timestamp: Date(),
            locationType: locType,
            vehicle: vehicleSnapshot,
            mobile: mobileSnapshot,
            verification: verification
        )

        record.vehicleID = vin.isEmpty ? nil : vin
        record.vehicleUpdatedAt = Date()
        DispatchQueue.main.async {
            guard ParkingWritePolicy.canComplete(revision: revision, currentRevision: self.recordRevision, vin: vin, selectedVIN: self.selectedVehicleID) else { return }
            self.saveRecord(record)
        }
    }

    // MARK: - Process Photo with Universal Classification & Cross-Verification

    @MainActor func processParkingPhoto(
        image: UIImage,
        vehicleTelemetry: Object
    ) async {
        let original = latestRecord
        let selectedVIN = selectedVehicleID
        guard ParkingWritePolicy.canAttachPhoto(recordVIN: original?.vehicleID, selectedVIN: selectedVIN) else {
            fleetParkingStatus = "다른 차량의 기록이므로 사진을 덮어쓸 수 없음"
            return
        }
        DispatchQueue.main.async { self.isAnalyzing = true }
        defer { DispatchQueue.main.async { self.isAnalyzing = false } }

        // 1. Save photo locally
        let fileName = "parking_\(Int(Date().timeIntervalSince1970)).jpg"
        let photoURL = getDocumentsDirectory().appendingPathComponent(fileName)
        if let jpegData = image.jpegData(compressionQuality: 0.85) {
            try? jpegData.write(to: photoURL)
        }

        // 2. Extract vehicle snapshot
        let vehicleSnapshot = original?.vehicle ?? self.buildVehicleSnapshot(from: vehicleTelemetry.isEmpty ? self.cachedVehicleTelemetry : vehicleTelemetry)

        // 3. Perform Apple Vision OCR
        let ocr = await recognizeUniversalParkingText(from: image)

        // 4. Build Mobile Snapshot
        var mobileSnapshot = MobileParkingSnapshot()
        mobileSnapshot = original?.mobile ?? mobileSnapshot
        mobileSnapshot.photoFileName = fileName
        mobileSnapshot.ocrFloor = ocr.floor
        mobileSnapshot.ocrPillar = ocr.pillar
        mobileSnapshot.ocrSpecialZone = ocr.specialZone
        mobileSnapshot.rawOcrText = ocr.rawText

        let phoneLoc = self.currentPhoneLocation
        if let loc = phoneLoc, abs(loc.timestamp.timeIntervalSinceNow) <= 30 {
            mobileSnapshot.mobileLatitude = loc.coordinate.latitude
            mobileSnapshot.mobileLongitude = loc.coordinate.longitude
            mobileSnapshot.horizontalAccuracy = loc.horizontalAccuracy
            mobileSnapshot.altitude = loc.altitude
        }

        // 5. Geocode with fallback
        let refLat = vehicleSnapshot.vehicleLatitude
        let refLng = vehicleSnapshot.vehicleLongitude
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
            if ocr.isUnderground || (ocr.floor != nil && ocr.floor!.contains("지하")) {
                return .underground
            }
            if let floor = ocr.floor, (floor.contains("F") || floor.contains("층")) && !floor.contains("1") {
                return .tower
            }
            return (ocr.pillar != nil) ? .underground : .outdoor
        }()

        // 8. Package full smart record
        var record = SmartParkingRecord(
            id: original?.id ?? UUID(),
            timestamp: original?.timestamp ?? Date(),
            locationType: locationType,
            vehicle: vehicleSnapshot,
            mobile: mobileSnapshot,
            verification: verification
        )
        record.vehicleID = original?.vehicleID
        record.vehicleUpdatedAt = original?.vehicleUpdatedAt

        DispatchQueue.main.async {
            guard self.latestRecord?.id == original?.id, self.selectedVehicleID == selectedVIN else { return }
            if let current = self.latestRecord {
                record = current.replacingPhotoMetadata(record.mobile)
                record.locationType = locationType
                record.verification = self.performCrossVerification(vehicle: current.vehicle, mobile: record.mobile, ocr: ocr)
            }
            self.saveRecord(record)
            self.showCapturePrompt = false
        }
    }

    // MARK: - Vehicle Snapshot Builder

    private func buildVehicleSnapshot(from telemetry: Object) -> VehicleParkingSnapshot {
        func recent(_ name: String) -> Object {
            let group = telemetry.object(name)
            guard let at = group.number("at"), at.isFinite else { return [:] }
            let age = Date().timeIntervalSince1970 * 1000 - at
            return age >= -5000 && age <= 120000 ? group : [:]
        }
        let drive = recent("drive"), loc = recent("location"), closures = recent("closures")
        let charge = recent("charge"), climate = recent("climate")

        var snap = VehicleParkingSnapshot()
        snap.gear = drive["gear"] as? String
        snap.odometerKm = drive.number("odometerKm")

        let headingDeg = loc.number("heading") ?? drive.number("heading")
        snap.heading = headingDeg
        if let deg = headingDeg {
            snap.headingDescription = headingToCardinal(deg)
        }

        snap.vehicleLatitude = loc.number("latitude")
        snap.vehicleLongitude = loc.number("longitude")
        snap.positionStatus = loc["positionStatus"] as? String

        // Closures & Security
        snap.isLocked = closures["locked"] as? Bool
        let doors = ["driverFront", "driverRear", "passengerFront", "passengerRear"].compactMap { closures[$0] as? Bool }
        snap.areDoorsClosed = doors.contains(true) ? false : (doors.count == 4 ? true : nil)
        snap.isTrunkClosed = (closures["trunk"] as? Bool).map { !$0 }
        snap.isFrunkClosed = (closures["frunk"] as? Bool).map { !$0 }

        // Charge
        snap.soc = charge.number("soc")
        snap.rangeKm = charge.number("rangeKm")
        snap.isCharging = charge["isCharging"] as? Bool
        if snap.isCharging == nil, let state = charge.number("charging"), state > 0 { snap.isCharging = state == 5 }
        snap.chargerKW = charge.number("chargerKW")
        snap.minutesToLimit = charge.number("minutesToLimit").flatMap { $0.isFinite && $0 >= 0 ? Int($0.rounded()) : nil }
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
            } else {
                ver.isLocationVerified = false
                ver.locationVerificationNote = "차량과 모바일 간 거리 차이 발생 (\(Int(dist))m)"
            }
        } else {
            ver.isLocationVerified = false
            ver.locationVerificationNote = "차량·휴대폰 위치 교차 확인 자료 부족"
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
            ver.isSecurityVerified = vehicle.isLocked == true && vehicle.areDoorsClosed == true && vehicle.isTrunkClosed == true && vehicle.isFrunkClosed == true
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
            ver.overallStatus = "위치 교차 확인 필요"
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
