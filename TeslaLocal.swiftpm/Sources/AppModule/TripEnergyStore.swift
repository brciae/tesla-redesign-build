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
    private var observedOdometer: (value: Double, at: Date)?
    private var lastCheckpoint = Date.distantPast
    private var chargingScannedAt = Date.distantPast
    private var selectedVIN = ""
    private let defaults: UserDefaults
    private let storageKey = "energy.tripForecast.v1"
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey + ".records"), data.count <= 2097152,
           let rows = try? JSONDecoder().decode([TripEnergyRecord].self, from: data) {
            records = Array(rows.suffix(50))
        }
        if let data = defaults.data(forKey: storageKey + ".session"), data.count <= 131072 {
            session = try? JSONDecoder().decode(TripEnergyRecord.self, from: data)
        }
    }
    func update(vin: String, state: Object, health: Object, nav: Object, guiding: Bool,
                routeKey: String, destination: String, soc: Double?, socAt: Date?, now: Date = Date(), force: Bool = false) {
        guard !vin.isEmpty else { estimate = nil; return }
        if selectedVIN != vin { selectedVIN = vin; profileKey = ""; estimate = nil; observedSOC = nil; observedOdometer = nil }
        if let soc, soc.isFinite, (0...100).contains(soc), let socAt, (-5...120).contains(now.timeIntervalSince(socAt)) {
            observedSOC = (soc, socAt)
        }
        let drive = state.object("groups").object("drive")
        if state.object("settings").string("vin") == vin, let at = drive.number("at"),
           (-5000...120000).contains(now.timeIntervalSince1970 * 1000 - at), let odo = drive.number("odometerKm"), (0...1e7).contains(odo) {
            observedOdometer = (odo, Date(timeIntervalSince1970: at / 1000))
        }
        if force || now.timeIntervalSince(chargingScannedAt) >= 5 {
            updateChargingStops(state: state, vin: vin, now: now); chargingScannedAt = now
        }
        // Cached or missing readings must not masquerade as a live arrival forecast.
        guard guiding, let at = nav.number("at"), (-5...10).contains(now.timeIntervalSince1970 - at), nav.flag("valid"),
              let metres = nav.number("remainMetres"), metres.isFinite, metres >= 0,
              let observedSOC, (-5...120).contains(now.timeIntervalSince(observedSOC.at)), !routeKey.isEmpty else {
            estimate = nil; return
        }
        guard force || now.timeIntervalSince(updatedAt) >= 5 || estimate == nil || session?.routeKey != routeKey else { return }
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
                startedAt: now, startSOC: observedSOC.value, initial: next,
                startOdometerKm: observedOdometer.flatMap { (-5...120).contains(now.timeIntervalSince($0.at)) ? $0.value : nil })
            appendPoint(now: now, force: true); save(); lastCheckpoint = now
        }
        appendPoint(now: now)
        if now.timeIntervalSince(lastCheckpoint) >= 120 { save(); lastCheckpoint = now }
        if !state.object("activeCharge").isEmpty || state.object("groups").object("charge").number("charging") == 5 ||
           observedSOC.value > (session?.startSOC ?? 100) + 1 {
            if session?.chargingObserved == false { session?.chargingObserved = true; save() }
        }
    }
    func finish(arrived: Bool, vin: String, now: Date = Date()) {
        defer { estimate = nil }
        appendPoint(now: now, force: true)
        guard var row = session, row.vin == vin else { return }
        row.endedAt = now; row.arrived = arrived
        if arrived, let observedSOC, (-5...120).contains(now.timeIntervalSince(observedSOC.at)) {
            row.actualArrivalSOC = observedSOC.value
            if observedSOC.value > row.startSOC + 1 { row.chargingObserved = true }
        }
        records.append(row); records = Array(records.suffix(50)); session = nil; save(writeRecords: true)
    }
    func history(vin: String) -> [TripEnergyRecord] { Array(records.filter { $0.vin == vin }.reversed()) }
    func invalidateProfile() { profileKey = "" }
    private func updateChargingStops(state: Object, vin: String, now: Date) {
        guard var row = session, row.vin == vin, state.object("settings").string("vin") == vin else { return }
        var stops = row.chargingStops ?? []
        let active = state.object("activeCharge")
        let candidates = Array(state.rows("charges").suffix(100)) + (active.isEmpty ? [] : [active])
        var changed = false
        for c in candidates {
            guard let start = c.number("at"), start >= row.startedAt.timeIntervalSince1970 * 1000,
                  start <= now.timeIntervalSince1970 * 1000 + 5000 else { continue }
            let end = c.number("end").flatMap { $0 >= start && $0 <= now.timeIntervalSince1970 * 1000 + 5000 ? $0 : nil }
            var stop = TripEnergyChargingStop(id: c.string("id", "charge:\(start)"), startedAt: Date(timeIntervalSince1970: start / 1000),
                endedAt: end.map { Date(timeIntervalSince1970: $0 / 1000) },
                startSOC: c.flag("startSOCObserved") && !c.flag("startSOCEstimated") ? c.number("startSOC") : nil,
                endSOC: end != nil && c.flag("endSOCObserved") && !c.flag("endSOCEstimated") ? c.number("endSOC") : nil,
                batteryAddedKWh: c.number("vehicleReportedKWh").flatMap { (0...300).contains($0) ? $0 : nil })
            if let index = stops.firstIndex(where: { old in
                old.id == stop.id || abs(old.startedAt.timeIntervalSince(stop.startedAt)) < 60 ||
                old.startedAt < (stop.endedAt ?? now) && stop.startedAt < (old.endedAt ?? now)
            }) {
                let old = stops[index]
                // A duplicate receipt or active row must not erase an observed completed charge.
                if old.addedSOC != nil && stop.addedSOC == nil { continue }
                if old.addedSOC != nil, stop.addedSOC != nil, let a = old.endedAt, let b = stop.endedAt,
                   old.startedAt <= stop.startedAt, a >= b, old.startedAt < stop.startedAt || a > b { continue }
                stop.id = old.id
                if stops[index] != stop { stops[index] = stop; changed = true }
            } else { stops.append(stop); changed = true }
        }
        if changed {
            if stops.count > 50 { row.chargingDataIncomplete = true }
            row.chargingStops = Array(stops.sorted { $0.startedAt < $1.startedAt }.prefix(50)); row.chargingObserved = true
            session = row; save()
        }
    }
    private func appendPoint(now: Date, force: Bool = false) {
        guard var row = session, row.vin == selectedVIN, let observedSOC,
              (-5...120).contains(now.timeIntervalSince(observedSOC.at)) else { return }
        var points = row.points ?? []
        let elapsed = max(0, observedSOC.at.timeIntervalSince(row.startedAt))
        guard elapsed >= (points.last?.elapsedSeconds ?? 0) else { return }
        guard force || elapsed - (points.last?.elapsedSeconds ?? -60) >= 60 else { return }
        var distance: Double?
        if let start = row.startOdometerKm, let odo = observedOdometer,
           (-5...120).contains(now.timeIntervalSince(odo.at)), abs(odo.at.timeIntervalSince(observedSOC.at)) <= 30 {
            let travelled = odo.value - start
            if travelled.isFinite, (0...3000).contains(travelled), travelled >= (points.last?.distanceKm ?? 0) { distance = travelled }
        }
        let point = TripEnergyPoint(elapsedSeconds: elapsed, distanceKm: distance,
            predictedSOC: distance.flatMap { row.predictedSOC(distanceKm: $0, at: observedSOC.at, actualSOC: observedSOC.value) }, actualSOC: observedSOC.value)
        if points.last?.elapsedSeconds == elapsed { points[points.count - 1] = point } else { points.append(point) }
        // Keep the full trip span when sampling longer journeys, without unbounded graph data.
        if points.count > 120 {
            let last = points.last!
            points = points.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
            if points.last != last { points.append(last) }
        }
        row.points = points; session = row
    }
    private func save(writeRecords: Bool = false) {
        if let session, let data = try? JSONEncoder().encode(session), data.count <= 131072 {
            defaults.set(data, forKey: storageKey + ".session")
        } else if session == nil { defaults.removeObject(forKey: storageKey + ".session") }
        // History is written only at route completion; periodic checkpoints contain the current trip only.
        if writeRecords, let data = try? JSONEncoder().encode(records), data.count <= 2097152 {
            defaults.set(data, forKey: storageKey + ".records")
        }
    }
}
