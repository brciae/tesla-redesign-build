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
        // A sampled trip keeps its first prediction, actual observations, and the full time span after compaction.
        let graphStore = TripEnergyStore(defaults: defaults)
        for i in 0...250 {
            let time = now.addingTimeInterval(Double(i) * 60)
            var context = state
            context["groups"] = ["drive": ["at": time.timeIntervalSince1970 * 1000, "odometerKm": 100.0 + Double(i)]]
            graphStore.update(vin: "A", state: context, health: ["capacity": 72.0],
                nav: ["at": time.timeIntervalSince1970, "valid": true, "remainMetres": max(0, 250000.0 - Double(i) * 1000)],
                guiding: true, routeKey: "graph", destination: "그래프", soc: 90 - Double(i) * 0.2, socAt: time, now: time)
        }
        let end = now.addingTimeInterval(250 * 60)
        graphStore.finish(arrived: true, vin: "A", now: end)
        let graph = graphStore.history(vin: "A").first!, points = graph.points!
        precondition(points.count <= 120 && points.first!.elapsedSeconds == 0 && points.last!.elapsedSeconds == 15000)
        precondition(points.last!.actualSOC == 40 && points.last!.predictedSOC == 27.5)
        precondition(graph.actualUsedKWh == 36, "Observed 50%p is converted with the recorded capacity")
        let restoredGraph = TripEnergyStore(defaults: defaults).history(vin: "A").first!
        precondition(restoredGraph.points == points && restoredGraph.initial == graph.initial)
        let chargedStore = TripEnergyStore(defaults: defaults), departure = end.addingTimeInterval(60)
        let chargeStart = departure.addingTimeInterval(600), chargeEnd = departure.addingTimeInterval(1200)
        var activeCharge: Object = ["id": "road-charge", "at": chargeStart.timeIntervalSince1970 * 1000, "startSOC": 70.0, "startSOCObserved": true]
        func chargedUpdate(time: Date, soc: Double, odo: Double, remaining: Double, active: Object? = nil, completed: [Object] = []) {
            var context = state
            context["groups"] = ["drive": ["at": time.timeIntervalSince1970 * 1000, "odometerKm": odo]]
            context["charges"] = completed
            if let active { context["activeCharge"] = active }
            chargedStore.update(vin: "A", state: context, health: ["capacity": 72.0],
                nav: ["at": time.timeIntervalSince1970, "valid": true, "remainMetres": remaining], guiding: true,
                routeKey: "charged-journey", destination: "충전 포함 여정", soc: soc, socAt: time, now: time)
        }
        chargedUpdate(time: departure, soc: 80, odo: 200, remaining: 80000)
        chargedUpdate(time: chargeStart, soc: 70, odo: 240, remaining: 40000, active: activeCharge)
        activeCharge["end"] = chargeEnd.timeIntervalSince1970 * 1000
        activeCharge["endSOC"] = 90.0; activeCharge["endSOCObserved"] = true; activeCharge["vehicleReportedKWh"] = 14.4
        var duplicateReceipt = activeCharge; duplicateReceipt["id"] = "receipt"; duplicateReceipt["at"] = chargeStart.timeIntervalSince1970 * 1000 + 120000
        chargedUpdate(time: chargeEnd, soc: 90, odo: 240, remaining: 40000, completed: [activeCharge, duplicateReceipt])
        let arrival = departure.addingTimeInterval(1800)
        chargedUpdate(time: arrival, soc: 80, odo: 280, remaining: 0, completed: [activeCharge, duplicateReceipt])
        chargedStore.finish(arrived: true, vin: "A", now: arrival)
        let journey = chargedStore.history(vin: "A").first!
        precondition(journey.chargingObserved && journey.chargingAccounted && journey.chargingStops!.count == 1)
        precondition(journey.addedSOC == 20 && journey.actualUsedSOC == 20 && journey.errorSOC == 0)
        precondition(abs(journey.actualUsedKWh! - 14.4) < 0.001)
        precondition(journey.points!.last!.actualSOC == 80 && journey.points!.last!.predictedSOC == 80)
        let correctionStart = arrival.addingTimeInterval(60)
        chargedStore.update(vin: "A", state: state, health: ["capacity": 72.0], nav: ["at": correctionStart.timeIntervalSince1970, "valid": true, "remainMetres": 1000.0],
            guiding: true, routeKey: "soc-correction", destination: "보정", soc: 50, socAt: correctionStart, now: correctionStart)
        let correctionEnd = correctionStart.addingTimeInterval(60)
        chargedStore.update(vin: "A", state: state, health: ["capacity": 72.0], nav: ["at": correctionEnd.timeIntervalSince1970, "valid": true, "remainMetres": 0.0],
            guiding: true, routeKey: "soc-correction", destination: "보정", soc: 53, socAt: correctionEnd, now: correctionEnd)
        chargedStore.finish(arrived: true, vin: "A", now: correctionEnd)
        let correction = chargedStore.history(vin: "A").first!
        precondition(!correction.chargingObserved && correction.unexplainedSOCGain == true && correction.actualUsedSOC == nil)
        print("PASS: trip prediction, bounded durable graphs, observed charging accounting/deduplication, missing-data exclusion, reroute and VIN isolation")
    }
}
