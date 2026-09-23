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
    func sectionIsRecent(_ section: String, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(receivedAt)
        guard age >= 0, age <= 120, let at = number(section, "timestamp") else { return false }
        let nowMS = now.timeIntervalSince1970 * 1000
        return at <= nowMS + 5000 && nowMS - at <= 120000
    }
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
        charge["mode"] = sectionIsRecent("charge_state", now: now) ? "recent" : "cached"
        climate["mode"] = sectionIsRecent("climate_state", now: now) ? "recent" : "cached"
        charge["at"] = number("charge_state", "timestamp")
        climate["at"] = number("climate_state", "timestamp")
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
            location["mode"] = sectionIsRecent("drive_state", now: now) ? "recent" : "cached"
        } else { location["mode"] = coordinates ? "cached" : "missing" }
        return ["charge": charge, "climate": climate, "location": location, "drive": driveDisplay(now: now)]
    }

    func driveDisplay(now: Date = Date()) -> [String: Any] {
        var drive: [String: Any] = ["mode": sectionIsRecent("drive_state", now: now) ? "recent" : "cached", "receivedAt": receivedAt.timeIntervalSince1970 * 1000]
        drive["at"] = number("drive_state", "timestamp")
        if let gear = (payload["drive_state"] as? [String: Any])?["shift_state"] as? String, ["P", "D", "R", "N"].contains(gear) { drive["gear"] = gear }
        if let speed = number("drive_state", "speed"), speed >= 0 { drive["speedKmh"] = speed * 1.609344 }
        let raw = payload["drive_state"] as? [String: Any] ?? [:]
        drive["destination"] = raw["active_route_destination"] as? String
        drive["destinationLat"] = number("drive_state", "active_route_latitude")
        drive["destinationLng"] = number("drive_state", "active_route_longitude")
        drive["arrivalMinutes"] = number("drive_state", "active_route_minutes_to_arrival")
        if let miles = number("drive_state", "active_route_miles_to_arrival"), miles >= 0 { drive["arrivalKm"] = miles * 1.609344 }
        return drive
    }

    /// Missing permissions/fields are not a route cancellation. Only explicit empty values qualify.
    func navigationEvent(now: Date = Date()) -> [String: Any] {
        guard sectionIsRecent("drive_state", now: now) else { return ["type": "wait"] }
        let d = driveDisplay(now: now), raw = payload["drive_state"] as? [String: Any] ?? [:]
        let name = (raw["active_route_destination"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stamp = number("drive_state", "timestamp") ?? 0
        let receipt = receivedAt.timeIntervalSince1970 * 1000
        if let name, !name.isEmpty, let lat = number("drive_state", "active_route_latitude"), let lon = number("drive_state", "active_route_longitude"),
           (-90...90).contains(lat), (-180...180).contains(lon), !(lat == 0 && lon == 0) {
            let tokenData = try? JSONSerialization.data(withJSONObject: [name, lat, lon])
            return ["type": "route", "name": name, "latitude": lat, "longitude": lon, "at": stamp, "receivedAt": receipt,
                    "token": tokenData.flatMap { String(data: $0, encoding: .utf8) } ?? ""]
        }
        func explicitEmpty(_ key: String) -> Bool {
            guard let value = raw[key] else { return false }
            return value is NSNull || number("drive_state", key) == 0
        }
        let emptyName = raw["active_route_destination"] is NSNull || name == ""
        let parked = d["gear"] as? String == "P"
        if emptyName, explicitEmpty("active_route_minutes_to_arrival"), explicitEmpty("active_route_miles_to_arrival"),
           parked || (explicitEmpty("active_route_latitude") && explicitEmpty("active_route_longitude")) {
            return ["type": "absent", "at": stamp, "receivedAt": receipt, "parked": parked]
        }
        return ["type": "wait"]
    }

    /// Read-only translation. A missing Fleet shift_state is not proof of P.
    func parkingTelemetry(now: Date = Date()) -> [String: Any]? {
        guard sectionIsRecent("drive_state", now: now), let driveAt = number("drive_state", "timestamp"),
              driveAt <= now.timeIntervalSince1970 * 1000 + 5000,
              now.timeIntervalSince1970 * 1000 - driveAt <= 120000 else { return nil }
        let stamp = receivedAt.timeIntervalSince1970 * 1000
        var drive: [String: Any] = ["at": driveAt, "receivedAt": stamp]
        if let gear = (payload["drive_state"] as? [String: Any])?["shift_state"] as? String, ["P", "D", "R", "N"].contains(gear) { drive["gear"] = gear }
        if let speed = number("drive_state", "speed"), speed >= 0 { drive["speedKmh"] = speed * 1.609344 }
        if let odo = number("vehicle_state", "odometer") { drive["odometerKm"] = odo * 1.609344 }
        let overlay = homeOverlay(now: now)
        var closures: [String: Any] = ["at": number("vehicle_state", "timestamp") ?? 0]
        closures["locked"] = locked
        for (key, fleetKey) in [("driverFront", "df"), ("driverRear", "dr"), ("passengerFront", "pf"), ("passengerRear", "pr"), ("frunk", "ft"), ("trunk", "rt")] {
            if let value = number("vehicle_state", fleetKey), value >= 0 { closures[key] = value > 0 }
        }
        return ["drive": drive, "location": overlay["location"] ?? [:], "charge": overlay["charge"] ?? [:], "climate": overlay["climate"] ?? [:], "closures": closures]
    }
}
