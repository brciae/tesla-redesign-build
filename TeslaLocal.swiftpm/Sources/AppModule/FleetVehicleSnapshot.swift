import Foundation
import CoreFoundation

/// Read-only Fleet display data. Never promoted to BLE verification or automation evidence.
struct FleetVehicleSnapshot {
    let vin: String
    let receivedAt: Date
    let payload: [String: Any]

    private func number(_ section: String, _ key: String) -> Double? {
        guard let value = (payload[section] as? [String: Any])?[key] as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
    private func flag(_ section: String, _ key: String) -> Bool? {
        (payload[section] as? [String: Any])?[key] as? Bool
    }
    var soc: Double? { number("charge_state", "battery_level").flatMap { (0...100).contains($0) ? $0 : nil } }
    var rangeKm: Double? { number("charge_state", "battery_range").flatMap { $0 >= 0 ? $0 * 1.609344 : nil } }
    var insideC: Double? { number("climate_state", "inside_temp") }
    var outsideC: Double? { number("climate_state", "outside_temp") }
    var locked: Bool? { flag("vehicle_state", "locked") }
    var charging: Bool { (payload["charge_state"] as? [String: Any])?["charging_state"] as? String == "Charging" }
    var hasMeasurements: Bool { soc != nil || insideC != nil || locked != nil }
    func isRecent(now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(receivedAt)
        guard age >= 0 && age <= 120 else { return false }
        let stamps = ["charge_state", "climate_state", "vehicle_state"].compactMap { number($0, "timestamp") }
        return !stamps.isEmpty && stamps.allSatisfy { $0 <= now.timeIntervalSince1970 * 1000 + 5000 && now.timeIntervalSince1970 * 1000 - $0 <= 120000 }
    }
    func homeOverlay(now: Date = Date()) -> [String: Any] {
        let recent = isRecent(now: now)
        let meta: [String: Any] = ["mode": recent ? "recent" : "cached", "label": recent ? "Fleet 최근 조회" : "Fleet 마지막 수신", "at": receivedAt.timeIntervalSince1970 * 1000]
        var charge = meta, climate = meta
        charge["soc"] = soc; charge["rangeKm"] = rangeKm
        if let status = (payload["charge_state"] as? [String: Any])?["charging_state"] as? String,
           ["Charging", "Stopped", "Complete", "Disconnected", "NoPower", "Starting"].contains(status) { charge["charging"] = charging; charge["isCharging"] = charging }
        charge["chargerKW"] = number("charge_state", "charger_power")
        charge["limit"] = number("charge_state", "charge_limit_soc")
        charge["addedKWh"] = number("charge_state", "charge_energy_added")
        if let hours = number("charge_state", "time_to_full_charge") { charge["minutesToLimit"] = hours * 60 }
        climate["insideC"] = insideC; climate["outsideC"] = outsideC
        climate["isOn"] = flag("climate_state", "is_climate_on")
        climate["targetC"] = number("climate_state", "driver_temp_setting")
        var location = meta
        let lat = number("drive_state", "latitude"), lon = number("drive_state", "longitude")
        let coordinates = lat != nil && lon != nil && (-90...90).contains(lat!) && (-180...180).contains(lon!) && !(lat == 0 && lon == 0)
        location["hasCoordinates"] = coordinates
        if coordinates { location["latitude"] = lat; location["longitude"] = lon }
        location["gpsAt"] = number("drive_state", "timestamp")
        if let at = number("drive_state", "timestamp"), now.timeIntervalSince1970 * 1000 - at <= 120000, at <= now.timeIntervalSince1970 * 1000 + 5000 {
            location["mode"] = recent ? "recent" : "cached"
        } else { location["mode"] = coordinates ? "cached" : "missing" }
        return ["charge": charge, "climate": climate, "location": location]
    }

    /// Read-only translation. A missing Fleet shift_state is not proof of P.
    func parkingTelemetry(now: Date = Date()) -> [String: Any]? {
        guard isRecent(now: now), let driveAt = number("drive_state", "timestamp"),
              driveAt <= now.timeIntervalSince1970 * 1000 + 5000,
              now.timeIntervalSince1970 * 1000 - driveAt <= 120000 else { return nil }
        let stamp = receivedAt.timeIntervalSince1970 * 1000
        var drive: [String: Any] = ["at": driveAt, "receivedAt": stamp]
        if let gear = (payload["drive_state"] as? [String: Any])?["shift_state"] as? String, ["P", "D", "R", "N"].contains(gear) { drive["gear"] = gear }
        if let speed = number("drive_state", "speed"), speed >= 0 { drive["speedKmh"] = speed * 1.609344 }
        if let odo = number("vehicle_state", "odometer") { drive["odometerKm"] = odo * 1.609344 }
        let overlay = homeOverlay(now: now)
        var closures: [String: Any] = ["at": stamp]
        closures["locked"] = locked
        for (key, fleetKey) in [("driverFront", "df"), ("driverRear", "dr"), ("passengerFront", "pf"), ("passengerRear", "pr"), ("frunk", "ft"), ("trunk", "rt")] {
            if let value = number("vehicle_state", fleetKey), value >= 0 { closures[key] = value > 0 }
        }
        return ["drive": drive, "location": overlay["location"] ?? [:], "charge": overlay["charge"] ?? [:], "climate": overlay["climate"] ?? [:], "closures": closures]
    }
}
