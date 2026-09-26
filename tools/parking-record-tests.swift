import Foundation

@main struct ParkingRecordTests {
    static func main() throws {
        var zoneRecord = SmartParkingRecord()
        zoneRecord.locationType = .evCharging
        zoneRecord.vehicle.isCharging = false
        zoneRecord.refreshLocationType()
        precondition(zoneRecord.locationType == .general)
        zoneRecord.mobile.ocrSpecialZone = "전기차 충전구역"
        zoneRecord.refreshLocationType()
        precondition(zoneRecord.locationType == .evCharging)

        var original = SmartParkingRecord()
        original.vehicleID = "A"
        original.timestamp = Date(timeIntervalSince1970: 1000)
        original.vehicle.vehicleLatitude = 37.5
        original.vehicle.vehicleLongitude = 127.1
        original.vehicle.soc = 62
        original.mobile.mobileLatitude = 1
        original.mobile.mobileLongitude = 2
        original.mobile.photoFileName = "before.jpg"
        var photo = original.mobile
        photo.photoFileName = "after.jpg"
        photo.ocrFloor = "지하 2층"
        let updated = original.replacingPhotoMetadata(photo)
        precondition(updated.id == original.id && updated.timestamp == original.timestamp)
        precondition(updated.vehicleID == "A" && updated.vehicle == original.vehicle)
        precondition(updated.effectiveLatitude == 37.5 && updated.effectiveLongitude == 127.1)
        precondition(updated.mobile.photoFileName == "after.jpg" && updated.mobile.ocrFloor == "지하 2층")
        precondition(!ParkingWritePolicy.canComplete(revision: 1, currentRevision: 2, vin: "A", selectedVIN: "A"))
        precondition(!ParkingWritePolicy.canComplete(revision: 1, currentRevision: 1, vin: "A", selectedVIN: "B"))
        precondition(ParkingWritePolicy.canComplete(revision: 1, currentRevision: 1, vin: "A", selectedVIN: "A"))
        precondition(!ParkingWritePolicy.canAttachPhoto(recordVIN: "A", selectedVIN: "B"))
        precondition(!ParkingWritePolicy.canAttachPhoto(recordVIN: "A", selectedVIN: ""))
        precondition(ParkingWritePolicy.canAttachPhoto(recordVIN: "A", selectedVIN: "A"))
        var unknown = SmartParkingRecord()
        unknown.mobile.mobileLatitude = 1; unknown.mobile.mobileLongitude = 2
        precondition(unknown.effectiveLatitude == nil && unknown.effectiveLongitude == nil)
        precondition(unknown.vehicle.gear == nil && unknown.vehicle.areDoorsClosed == nil)
        precondition(unknown.vehicle.securityText == "잠금 상태 미수신")
        precondition(unknown.vehicle.batteryText == "잔량 미수신")
        unknown.vehicle.isLocked = true
        precondition(unknown.vehicle.securityText == "잠김 · 도어 상태 미수신")
        unknown.vehicle.areDoorsClosed = true; unknown.vehicle.isTrunkClosed = true; unknown.vehicle.isFrunkClosed = true
        precondition(unknown.vehicle.securityText == "잠김 · 도어 닫힘")
        unknown.vehicle.isTrunkClosed = false
        precondition(unknown.vehicle.securityText == "도어 또는 트렁크 열림")
        unknown.vehicle.soc = 60; unknown.vehicle.isCharging = false
        precondition(unknown.vehicle.batteryText == "60% · 충전 안 함")
        precondition(updated.briefingLines.joined().contains("지하 2층"))
        let encoded = try JSONEncoder().encode(updated)
        let decoded = try JSONDecoder().decode(SmartParkingRecord.self, from: encoded)
        precondition(decoded == updated)
        print("PASS: parking record time/ID/vehicle/photo preservation, VIN/revision guards, phone separation and Codable round trip")
    }
}
