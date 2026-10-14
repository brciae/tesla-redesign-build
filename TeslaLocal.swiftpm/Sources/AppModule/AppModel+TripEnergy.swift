import Foundation

extension AppModel {
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
