import Foundation
import Combine

/// Bounded native presentation cache. No JS analytics or disk writes on each navigation packet.
final class TripEnergyStore: ObservableObject {
    static let shared = TripEnergyStore()
    @Published private(set) var estimate: TripEnergyEstimate?
    @Published private(set) var records: [TripEnergyRecord] = []
    private var session: TripEnergyRecord?
    private var profile = TripEnergyProfile.make(samples: [], usableKWh: nil)
    private var profileKey = ""
    private var updatedAt = Date.distantPast
    private var observedSOC: (value: Double, at: Date)?
    private var selectedVIN = ""
    private let defaults: UserDefaults
    private let storageKey = "energy.tripForecast.v1"
    private struct Saved: Codable { var records: [TripEnergyRecord]; var session: TripEnergyRecord? }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey), data.count <= 262144,
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            records = Array(saved.records.suffix(50)); session = saved.session
        }
    }
    func update(vin: String, state: Object, health: Object, nav: Object, guiding: Bool,
                routeKey: String, destination: String, soc: Double?, socAt: Date?, now: Date = Date()) {
        guard !vin.isEmpty else { estimate = nil; return }
        if selectedVIN != vin { selectedVIN = vin; profileKey = ""; estimate = nil; observedSOC = nil }
        if let soc, soc.isFinite, (0...100).contains(soc), let socAt, (-5...120).contains(now.timeIntervalSince(socAt)) {
            observedSOC = (soc, socAt)
        }
        // Cached or missing readings must not masquerade as a live arrival forecast.
        guard guiding, let at = nav.number("at"), (-5...10).contains(now.timeIntervalSince1970 - at), nav.flag("valid"),
              let metres = nav.number("remainMetres"), metres.isFinite, metres >= 0,
              let observedSOC, (-5...120).contains(now.timeIntervalSince(observedSOC.at)), !routeKey.isEmpty else {
            estimate = nil; return
        }
        guard now.timeIntervalSince(updatedAt) >= 5 || estimate == nil || session?.routeKey != routeKey else { return }
        updatedAt = now
        let trips = state.rows("trips"), settings = state.object("settings")
        // Never train on another vehicle's records while Fleet selection is changing.
        let sameVehicle = settings.string("vin") == vin
        let capacity = sameVehicle ? health.number("capacity") : nil
        let batteryStart = settings.number("healthBatteryStartAt") ?? 0
        let key = "\(vin):\(trips.count):\(trips.last?.string("id") ?? ""):\(capacity ?? -1):\(settings.number("assumedCapacityKWh") ?? 75):\(batteryStart)"
        if profileKey != key {
            profileKey = key
            let charges = Array(state.rows("charges").suffix(100))
            var occupied = -Double.infinity
            let samples: [TripEnergySample] = sameVehicle ? Array(trips.suffix(80)).sorted { ($0.number("start") ?? 0) < ($1.number("start") ?? 0) }.compactMap { t in
                guard let start = t.number("start"), start >= batteryStart, let end = t.number("end"), end > start, end <= now.timeIntervalSince1970 * 1000 + 5000,
                      let km = t.number("distanceKm"), let a = t.number("startSOC"), let b = t.number("endSOC") else { return nil }
                let duplicate = start < occupied; occupied = max(occupied, end)
                let mixed = charges.contains { c in
                    guard let a = c.number("at"), let b = c.number("end") else { return false }; return start < b && a < end
                }
                return .init(distanceKm: km, startSOC: a, endSOC: b, complete: !t.flag("missing") && !duplicate, mixedCharging: mixed)
            } : []
            profile = .make(samples: samples, usableKWh: capacity, assumedKWh: settings.number("assumedCapacityKWh") ?? 75)
        }
        var activeSample: TripEnergySample?
        let active = state.object("activeTrip")
        if sameVehicle, let km = active.number("distanceKm"), let start = active.number("startSOC"),
           let at = active.number("lastAt"), (-5000...120000).contains(now.timeIntervalSince1970 * 1000 - at),
           state.object("activeCharge").isEmpty {
            activeSample = .init(distanceKm: km, startSOC: start, endSOC: observedSOC.value, complete: !active.flag("missing"))
        }
        guard let next = TripEnergyEstimate.calculate(profile: profile, soc: observedSOC.value, remainingKm: metres / 1000,
                active: activeSample, reserveSOC: settings.number("reserveSOC") ?? 20, positionEstimated: nav.flag("positionEstimated")) else { estimate = nil; return }
        if let current = session, (!current.resumable(vin: vin, now: now) || current.routeKey != routeKey) {
            finish(arrived: false, vin: current.vin, now: now)
        }
        estimate = next
        if session == nil {
            session = TripEnergyRecord(vin: vin, routeKey: routeKey, destination: destination,
                startedAt: now, startSOC: observedSOC.value, initial: next)
            save()
        }
        if !state.object("activeCharge").isEmpty || state.object("groups").object("charge").number("charging") == 5 ||
           observedSOC.value > (session?.startSOC ?? 100) + 1 {
            if session?.chargingObserved == false { session?.chargingObserved = true; save() }
        }
    }
    func finish(arrived: Bool, vin: String, now: Date = Date()) {
        defer { estimate = nil }
        guard var row = session, row.vin == vin else { return }
        row.endedAt = now; row.arrived = arrived
        if arrived, let observedSOC, (-5...120).contains(now.timeIntervalSince(observedSOC.at)) {
            row.actualArrivalSOC = observedSOC.value
            if observedSOC.value > row.startSOC + 1 { row.chargingObserved = true }
        }
        records.append(row); records = Array(records.suffix(50)); session = nil; save()
    }
    func history(vin: String) -> [TripEnergyRecord] { Array(records.filter { $0.vin == vin }.reversed()) }
    func invalidateProfile() { profileKey = "" }
    private func save() {
        guard let data = try? JSONEncoder().encode(Saved(records: records, session: session)), data.count <= 262144 else { return }
        defaults.set(data, forKey: storageKey)
    }
}
