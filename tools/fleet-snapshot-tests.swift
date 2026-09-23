import Foundation

@main struct FleetSnapshotTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 1800000000)
        let ms = now.timeIntervalSince1970 * 1000
        let snapshot = FleetVehicleSnapshot(vin: "TEST", receivedAt: now, payload: [
            "charge_state": ["battery_level": 72, "battery_range": 100, "charging_state": "Charging", "timestamp": ms],
            "climate_state": ["inside_temp": 0, "outside_temp": -5, "timestamp": ms],
            "vehicle_state": ["locked": false, "timestamp": ms, "odometer": 1000]
        ])
        precondition(abs((snapshot.driveDisplay(now: now)["odometerKm"] as? Double ?? 0) - 1609.344) < 0.001)
        let supplement = FleetSupplementResult(vin: "TEST", receivedAt: now, payload: ["superchargers": [["name": "충전소 A", "available_stalls": 3, "total_stalls": 8, "internal_id": "hidden"]]])
        precondition(supplement.cards.count == 1)
        precondition(supplement.cards[0].rows.contains { $0.label == "사용 가능" && $0.value == "3" })
        precondition(!supplement.cards[0].rows.contains { $0.value == "hidden" })
        let sections = snapshot.insightSections()
        precondition(sections.count == 5)
        precondition(sections.first(where: { $0.title == "타이어 상태" })!.rows.first!.value == "미수신")
        precondition(snapshot.flattenedFields(section: "charge_state").contains(where: { $0.label == "charge_state.battery_level" && $0.value == "72" }))
        let nested = FleetVehicleSnapshot(vin: "TEST", receivedAt: now, payload: ["vehicle_state": ["software_update": ["status": "available"], "missing": NSNull()]])
        precondition(nested.flattenedFields(section: "vehicle_state").count == 2)
        precondition(nested.flattenedFields(section: "vehicle_state").contains(where: { $0.value == "미수신 (null)" }))
        precondition(snapshot.soc == 72 && abs(snapshot.rangeKm! - 160.9344) < 0.00001)
        precondition(snapshot.insideC == 0 && snapshot.outsideC == -5 && snapshot.locked == false)
        precondition(snapshot.charging && snapshot.hasMeasurements && snapshot.isRecent(now: now))
        precondition(!snapshot.isRecent(now: now.addingTimeInterval(121)))
        precondition(!snapshot.isRecent(now: now.addingTimeInterval(-1)))
        let empty = FleetVehicleSnapshot(vin: "TEST", receivedAt: now, payload: ["charge_state": ["battery_level": NSNull(), "battery_range": -1]])
        precondition(empty.soc == nil && empty.rangeKm == nil && empty.locked == nil && !empty.hasMeasurements)
        let stale = FleetVehicleSnapshot(vin: "TEST", receivedAt: now, payload: ["charge_state": ["battery_level": 30, "timestamp": ms - 900000]])
        precondition(!stale.isRecent(now: now))
        precondition((stale.homeOverlay(now: now)["charge"] as? [String: Any])?["mode"] as? String == "cached")
        let bool = FleetVehicleSnapshot(vin: "TEST", receivedAt: now, payload: ["charge_state": ["battery_level": true]])
        precondition(bool.soc == nil)
        precondition((empty.homeOverlay(now: now)["charge"] as? [String: Any])?["isCharging"] == nil)
        precondition((snapshot.homeOverlay(now: now)["charge"] as? [String: Any])?["isCharging"] as? Bool == true)
        let climate = FleetVehicleSnapshot(vin: "TEST", receivedAt: now, payload: ["climate_state": ["is_climate_on": false, "driver_temp_setting": 21.5, "timestamp": ms]])
        let overlay = climate.homeOverlay(now: now)["climate"] as? [String: Any]
        precondition(overlay?["isOn"] as? Bool == false && overlay?["targetC"] as? Double == 21.5)
        let parked = FleetVehicleSnapshot(vin: "TEST", receivedAt: now, payload: [
            "drive_state": ["shift_state": "P", "latitude": 37.5, "longitude": 127.1, "timestamp": ms],
            "vehicle_state": ["locked": true, "df": 0, "ft": 1, "timestamp": ms]])
        let telemetry = parked.parkingTelemetry(now: now)!
        precondition((telemetry["drive"] as? [String: Any])?["gear"] as? String == "P")
        precondition((telemetry["location"] as? [String: Any])?["latitude"] as? Double == 37.5)
        precondition((telemetry["closures"] as? [String: Any])?["driverFront"] as? Bool == false)
        precondition((telemetry["closures"] as? [String: Any])?["frunk"] as? Bool == true)
        precondition((telemetry["closures"] as? [String: Any])?["trunk"] == nil)
        let unknownGear = FleetVehicleSnapshot(vin: "TEST", receivedAt: now, payload: ["drive_state": ["shift_state": NSNull(), "timestamp": ms]])
        precondition((unknownGear.parkingTelemetry(now: now)?["drive"] as? [String: Any])?["gear"] == nil)
        let oldGPS = FleetVehicleSnapshot(vin: "TEST", receivedAt: now, payload: ["vehicle_state": ["timestamp": ms], "drive_state": ["shift_state": "P", "timestamp": ms - 900000, "latitude": 37.5, "longitude": 127.1]])
        precondition(oldGPS.parkingTelemetry(now: now) == nil)
        let mixed = FleetVehicleSnapshot(vin: "TEST", receivedAt: now, payload: ["drive_state": ["shift_state": "P", "timestamp": ms], "climate_state": ["timestamp": ms - 900000], "vehicle_state": ["timestamp": ms - 900000]])
        precondition(mixed.parkingTelemetry(now: now) != nil, "Fresh P survives stale climate/closures")
        precondition(mixed.driveDisplay(now: now)["gear"] as? String == "P")
        precondition(mixed.navigationEvent(now: now)["type"] as? String == "wait", "Omitted route fields cannot cancel guidance")
        let noRoute = FleetVehicleSnapshot(vin: "TEST", receivedAt: now, payload: ["drive_state": ["shift_state": "P", "timestamp": ms, "active_route_destination": NSNull(), "active_route_minutes_to_arrival": 0, "active_route_miles_to_arrival": 0]])
        precondition(noRoute.navigationEvent(now: now)["type"] as? String == "absent")
        precondition(noRoute.navigationEvent(now: now.addingTimeInterval(121))["type"] as? String == "wait")
        precondition((oldGPS.homeOverlay(now: now)["location"] as? [String: Any])?["mode"] as? String == "cached")
        print("PASS: Fleet display snapshot unit conversion, missing values, timestamps and stale-state labeling")
    }
}
