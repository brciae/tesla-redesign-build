import Foundation

extension AppModel {
    /// Display-only selection from data already collected. No extra Fleet polls or vehicle wakeups.
    /// Static charge-limit timestamps must not make a fresh Charging/Stopped sample disappear.
    func activityChargePresentation(now: Date = Date()) -> Object {
        var candidates: [Object] = []
        let ble = groups.object("charge")
        if let raw = ble.number("charging"), (0...100).contains(raw), let status = ChargeEventPolicy.bleState(Int(raw)), let at = ble.number("at") {
            var row = ble; row["status"] = status; row["at"] = at; candidates.append(row)
        }
        if let snapshot = fleet.vehicleSnapshot, snapshot.vin == energyVehicleVIN,
           let group = snapshot.payload["charge_state"] as? Object,
           let status = group["charging_state"] as? String, let at = snapshot.number("charge_state", "timestamp") {
            var row = snapshot.homeOverlay(now: now).object("charge")
            row["status"] = status; row["at"] = at; candidates.append(row)
        }
        let latest = FleetTelemetryData.latest(archiveReadings, vin: energyVehicleVIN)
        if let reading = latest["DetailedChargeState"], !reading.invalid,
           let data = reading.text.data(using: .utf8),
           let raw = try? JSONSerialization.jsonObject(with: data) as? Object,
           let detailed = raw["detailedChargeStateValue"] as? String {
            let status = String(detailed.dropFirst("DetailedChargeState".count))
            var row: Object = ["status": status, "at": reading.at.timeIntervalSince1970 * 1000]
            for (field, key, scale) in [("Soc", "soc", 1.0), ("ChargeLimitSoc", "limit", 1.0),
                ("TimeToFullCharge", "minutesToLimit", 60.0), ("ACChargingPower", "chargerKW", 1.0),
                ("DCChargingPower", "chargerKW", 1.0), ("ChargePower", "chargerKW", 1.0)] {
                guard let value = latest[field], !value.invalid, let number = value.number,
                      now.timeIntervalSince(value.at) >= -5,
                      key == "limit" || now.timeIntervalSince(value.at) <= 120 else { continue }
                row[key] = number * scale
            }
            candidates.append(row)
        }
        let states = ["Charging", "Stopped", "Complete", "Disconnected", "NoPower", "Starting", "Calibrating"]
        guard var row = candidates.filter({ states.contains($0.string("status")) &&
            ($0.number("at") ?? .infinity) <= now.timeIntervalSince1970 * 1000 + 5000 })
            .max(by: { ($0.number("at") ?? 0) < ($1.number("at") ?? 0) }) else { return [:] }
        row["mode"] = now.timeIntervalSince1970 * 1000 - (row.number("at") ?? 0) <= 120000 ? "recent" : "cached"
        return row
    }
    var energyVehicleVIN: String { fleet.selectedVin.isEmpty ? settings.string("vin") : fleet.selectedVin }
    func updateTripEnergy(force: Bool = false) {
        guard !demo else { return }
        let now = Date(), charge = groups.object("charge")
        var soc: Double?, socAt: Date?
        if output.object("fresh").flag("charge"), let at = charge.number("at") {
            soc = charge.number("soc"); socAt = Date(timeIntervalSince1970: at / 1000)
        } else if let snapshot = fleet.vehicleSnapshot, snapshot.vin == energyVehicleVIN,
                  snapshot.sectionIsRecent("charge_state", now: now), let at = snapshot.number("charge_state", "timestamp") {
            soc = snapshot.soc; socAt = Date(timeIntervalSince1970: at / 1000)
        }
        tripEnergy.update(vin: energyVehicleVIN, state: state, health: output.object("health"), nav: navigation.telemetry,
            guiding: navigation.guiding, routeKey: navigation.energyRouteKey, destination: navigation.energyDestination,
            soc: soc, socAt: socAt, now: now, force: force)
    }
}
