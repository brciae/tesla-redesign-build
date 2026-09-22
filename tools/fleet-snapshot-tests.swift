import Foundation

@main struct FleetSnapshotTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 1800000000)
        let ms = now.timeIntervalSince1970 * 1000
        let snapshot = FleetVehicleSnapshot(vin: "TEST", receivedAt: now, payload: [
            "charge_state": ["battery_level": 72, "battery_range": 100, "charging_state": "Charging", "timestamp": ms],
            "climate_state": ["inside_temp": 0, "outside_temp": -5, "timestamp": ms],
            "vehicle_state": ["locked": false, "timestamp": ms]
        ])
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
        precondition((oldGPS.homeOverlay(now: now)["location"] as? [String: Any])?["mode"] as? String == "cached")
        print("PASS: Fleet display snapshot unit conversion, missing values, timestamps and stale-state labeling")
    }
}
