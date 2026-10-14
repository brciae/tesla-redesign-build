import Foundation

// Same dictionary interface as production; native policy/store tested without SDK or vehicle access.
typealias Object = [String: Any]
extension Dictionary where Key == String, Value == Any {
    func object(_ key: String) -> Object { self[key] as? Object ?? [:] }
    func rows(_ key: String) -> [Object] { self[key] as? [Object] ?? [] }
    func string(_ key: String, _ fallback: String = "") -> String { self[key] as? String ?? fallback }
    func number(_ key: String) -> Double? { guard let v = (self[key] as? NSNumber)?.doubleValue, v.isFinite else { return nil }; return v }
    func flag(_ key: String) -> Bool { self[key] as? Bool ?? false }
}
@main struct TripEnergyTests {
    static func main() throws {
        let samples = Array(repeating: TripEnergySample(distanceKm: 40, startSOC: 80, endSOC: 70), count: 8)
        let profile = TripEnergyProfile.make(samples: samples, usableKWh: 72)
        let e = TripEnergyEstimate.calculate(profile: profile, soc: 68, remainingKm: 8.7)!
        precondition(abs(e.arrivalSOC - 65.825) < 0.001 && abs(e.remainingKWh - 1.566) < 0.001)
        precondition(e.lowSOC < e.arrivalSOC && e.highSOC > e.arrivalSOC && !e.capacityAssumed)
        precondition(TripEnergyEstimate.calculate(profile: profile, soc: .nan, remainingKm: 1) == nil)
        precondition(TripEnergyEstimate.calculate(profile: profile, soc: 50, remainingKm: .infinity) == nil)
        precondition(TripEnergyEstimate.calculate(profile: profile, soc: 101, remainingKm: 1) == nil)
        precondition(TripEnergyEstimate.calculate(profile: profile, soc: 50, remainingKm: -1) == nil)
        let empty = TripEnergyProfile.make(samples: [], usableKWh: nil)
        precondition(empty.capacityAssumed && empty.sampleCount == 0)
        for sample in [TripEnergySample(distanceKm: 4, startSOC: 80, endSOC: 70), .init(distanceKm: 40, startSOC: 80, endSOC: 79),
                       .init(distanceKm: 40, startSOC: 80, endSOC: 85), .init(distanceKm: 40, startSOC: 80, endSOC: 70, complete: false),
                       .init(distanceKm: 40, startSOC: 80, endSOC: 70, mixedCharging: true)] { precondition(sample.rate == nil) }
        let adjusted = TripEnergyEstimate.calculate(profile: profile, soc: 68, remainingKm: 8.7, active: .init(distanceKm: 20, startSOC: 80, endSOC: 68))!
        precondition(adjusted.liveAdjusted && adjusted.arrivalSOC < e.arrivalSOC)
        let tunnel = TripEnergyEstimate.calculate(profile: profile, soc: 68, remainingKm: 8.7, positionEstimated: true)!
        precondition(tunnel.highSOC >= e.highSOC && tunnel.lowSOC <= e.lowSOC)
        let shortage = TripEnergyEstimate.calculate(profile: profile, soc: 5, remainingKm: 100)!
        precondition(shortage.insufficient && shortage.belowReserve && shortage.arrivalSOC == 0)
        let zero = TripEnergyEstimate.calculate(profile: profile, soc: 20, remainingKm: 0)!
        precondition(zero.remainingKWh == 0 && zero.arrivalSOC == 20 && zero.lowSOC == 20)

        let suite = "TripEnergyTests." + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = Date(), store = TripEnergyStore(defaults: defaults)
        let t = now.timeIntervalSince1970 * 1000
        let state: Object = ["settings": ["vin": "A"], "trips": [["id": "one", "start": t - 3600000, "end": t - 1800000,
            "distanceKm": 40.0, "startSOC": 80.0, "endSOC": 70.0]], "charges": []]
        func update(_ route: String = "one", _ soc: Double? = 68, _ metres: Double = 8700, age: Double = 0, state context: Object? = nil, vin: String = "A") {
            store.update(vin: vin, state: context ?? state, health: ["capacity": 72.0],
                nav: ["at": now.timeIntervalSince1970 - age, "valid": true, "remainMetres": metres], guiding: true,
                routeKey: route, destination: "목적지", soc: soc, socAt: soc == nil ? nil : now, now: now)
        }
        update(); precondition(store.estimate?.sampleCount == 1)
        let initial = store.estimate!.arrivalSOC
        now.addTimeInterval(6); update("one", 67, 4000)
        precondition(store.estimate!.arrivalSOC > initial, "Remaining route must recalculate, not keep original distance")
        now.addTimeInterval(6); update(age: 11); precondition(store.estimate == nil)
        now.addTimeInterval(6); update("one", 66, 0)
        store = TripEnergyStore(defaults: defaults) // Process restoration preserves initial forecast, not old live SOC.
        precondition(store.estimate == nil)
        now.addTimeInterval(6); update("one", 66, 0); store.finish(arrived: true, vin: "A", now: now)
        let completed = store.history(vin: "A").first!
        precondition(completed.arrived && completed.initial.arrivalSOC == initial && completed.actualArrivalSOC == 66)
        precondition(abs(completed.errorSOC! - (66 - initial)) < 0.001 && completed.actualUsedSOC == 2)
        now.addTimeInterval(6); update()
        now.addTimeInterval(6); update("changed", 67, 20000)
        precondition(store.history(vin: "A").first?.arrived == false, "Changed destination closes comparison without fake arrival")
        var charging = state; charging["activeCharge"] = ["at": t]
        now.addTimeInterval(6); update("changed", 69, 19000, state: charging)
        store.finish(arrived: true, vin: "A", now: now)
        precondition(store.history(vin: "A").first?.errorSOC == nil, "Charging cannot become prediction error")
        now.addTimeInterval(6); update("unknown-end")
        now.addTimeInterval(121); store.finish(arrived: true, vin: "A", now: now)
        precondition(store.history(vin: "A").first?.actualArrivalSOC == nil, "Old SOC cannot establish arrival")
        now.addTimeInterval(6); update("other", vin: "B")
        precondition(store.estimate?.sampleCount == 0, "Other VIN history must not train prediction")
        store.finish(arrived: false, vin: "B", now: now)
        precondition(store.history(vin: "B").count == 1)
        precondition(TripEnergyStore(defaults: defaults).history(vin: "A").count == 4)
        print("PASS: trip prediction units, range, live correction, missing/stale data, reroute, durable initial-versus-arrival, charging exclusion and VIN isolation")
    }
}
