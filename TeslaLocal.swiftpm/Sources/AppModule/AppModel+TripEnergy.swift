import Foundation

extension AppModel {
    /// Display-only selection from data already collected. No extra Fleet polls or vehicle wakeups.
    /// Static charge-limit timestamps must not make a fresh Charging/Stopped sample disappear.
    func activityChargePresentation(now: Date = Date()) -> Object {
        var candidates: [Object] = []
        let ble = groups.object("charge")
        if settings.string("vin") == energyVehicleVIN, let raw = ble.number("charging"), (0...100).contains(raw),
           let status = ChargeEventPolicy.bleState(Int(raw)), let at = ble.number("at") {
            var row = ble; row["status"] = status; row["at"] = at; candidates.append(row)
        }
        if let snapshot = fleet.vehicleSnapshot, snapshot.vin == energyVehicleVIN,
           let group = snapshot.payload["charge_state"] as? Object,
           let status = group["charging_state"] as? String, let at = snapshot.number("charge_state", "timestamp") {
            var row = snapshot.homeOverlay(now: now).object("charge")
            row["status"] = status; row["at"] = at; candidates.append(row)
        }
        if let archive = FleetTelemetryData.liveActivityCharge(archiveReadings, vin: energyVehicleVIN, now: now) { candidates.append(archive) }
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
        func accept(_ value: Double?, at: Double?) {
            guard let value, value.isFinite, (0...100).contains(value), let at, at.isFinite,
                  (-5000...120000).contains(now.timeIntervalSince1970 * 1000 - at),
                  socAt == nil || at > socAt!.timeIntervalSince1970 * 1000 else { return }
            soc = value; socAt = Date(timeIntervalSince1970: at / 1000)
        }
        if settings.string("vin") == energyVehicleVIN {
            accept(charge.number("soc"), at: charge.number("at"))
        }
        if let snapshot = fleet.vehicleSnapshot, snapshot.vin == energyVehicleVIN {
            accept(snapshot.soc, at: snapshot.number("charge_state", "timestamp"))
        }
        let archive = FleetTelemetryData.latest(archiveReadings, vin: energyVehicleVIN)
        for key in ["Soc", "BatteryLevel"] {
            if let reading = archive[key], !reading.invalid { accept(reading.number, at: reading.at.timeIntervalSince1970 * 1000) }
        }
        tripEnergy.update(vin: energyVehicleVIN, state: state, health: output.object("health"), nav: navigation.telemetry,
            guiding: navigation.guiding, routeKey: navigation.energyRouteKey, destination: navigation.energyDestination,
            soc: soc, socAt: socAt, now: now, force: force)
    }
}
