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
        print("PASS: Fleet display snapshot unit conversion, missing values, timestamps and stale-state labeling")
    }
}
