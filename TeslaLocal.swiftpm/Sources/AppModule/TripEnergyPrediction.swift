import Foundation

/// SOC is learned directly; nominal BMS capacity is never treated as usable capacity.
struct TripEnergySample {
    var distanceKm: Double
    var startSOC: Double
    var endSOC: Double
    var complete = true
    var mixedCharging = false
    var rate: Double? {
        let drop = startSOC - endSOC
        guard complete, !mixedCharging, distanceKm.isFinite, distanceKm >= 5,
              startSOC.isFinite, endSOC.isFinite, (0...100).contains(startSOC), (0...100).contains(endSOC),
              drop >= 2, drop / distanceKm >= 0.02, drop / distanceKm <= 2 else { return nil }
        return drop / distanceKm
    }
}

struct TripEnergyProfile {
    var socPerKm: Double
    var relativeSpread: Double
    var sampleCount: Int
    var usableKWh: Double
    var capacityAssumed: Bool
    static func make(samples: [TripEnergySample], usableKWh: Double?, assumedKWh: Double = 75) -> Self {
        let rates = Array(samples.compactMap(\.rate).suffix(30)).sorted()
        let measured = usableKWh.flatMap { $0.isFinite && (20...200).contains($0) ? $0 : nil }
        let fallback = assumedKWh.isFinite && (20...200).contains(assumedKWh) ? assumedKWh : 75
        let capacity = measured ?? fallback
        let rate = median(rates) ?? (18 / capacity) // 180 Wh/km, explicitly a fallback assumption.
        let deviations = rates.map { abs($0 - rate) }
        let spread = (median(deviations) ?? 0) / rate * 2
        return .init(socPerKm: rate, relativeSpread: min(0.65, max(rates.count >= 5 ? 0.20 : 0.35, spread)),
                     sampleCount: rates.count, usableKWh: capacity, capacityAssumed: measured == nil)
    }
    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted(), i = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[i - 1] + sorted[i]) / 2 : sorted[i]
    }
}

struct TripEnergyEstimate: Codable, Equatable {
    var arrivalSOC: Double
    var rawArrivalSOC: Double
    var lowSOC: Double
    var highSOC: Double
    var remainingKWh: Double
    var socPerKm: Double
    var sampleCount: Int
    var liveAdjusted: Bool
    var capacityAssumed: Bool
    var capacityKWh: Double
    var insufficient: Bool
    var belowReserve: Bool
    var basis: String { liveAdjusted ? "현재 트립 보정" : sampleCount > 0 ? "개인 트립 \(sampleCount)회" : "기본 전비 가정" }

    static func calculate(profile: TripEnergyProfile, soc: Double, remainingKm: Double,
                          active: TripEnergySample? = nil, reserveSOC: Double = 20,
                          positionEstimated: Bool = false) -> Self? {
        guard soc.isFinite, (0...100).contains(soc), remainingKm.isFinite, (0...3000).contains(remainingKm),
              profile.socPerKm.isFinite, profile.socPerKm > 0, profile.usableKWh.isFinite,
              (20...200).contains(profile.usableKWh) else { return nil }
        var rate = profile.socPerKm, adjusted = false
        if let active, let current = active.rate {
            // SOC has about 1%p quantization. Never learn from a one-point drop or a short segment.
            let weight = min(0.7, active.distanceKm / 50)
            let bounded = min(rate * 2, max(rate * 0.5, current))
            rate = rate * (1 - weight) + bounded * weight; adjusted = true
        }
        let use = remainingKm * rate, arrival = soc - use
        let spread = min(0.8, max(profile.relativeSpread, profile.sampleCount == 0 ? 0.5 : 0) + (positionEstimated ? 0.1 : 0))
        let uncertainty = remainingKm == 0 ? 0 : max(1, use * spread)
        let reserve = reserveSOC.isFinite ? min(100, max(0, reserveSOC)) : 20
        return .init(arrivalSOC: min(100, max(0, arrival)), rawArrivalSOC: arrival, lowSOC: min(100, max(0, arrival - uncertainty)),
                     highSOC: min(100, max(0, arrival + uncertainty)), remainingKWh: use / 100 * profile.usableKWh,
                     socPerKm: rate, sampleCount: profile.sampleCount, liveAdjusted: adjusted,
                     capacityAssumed: profile.capacityAssumed, capacityKWh: profile.usableKWh, insufficient: arrival < 0, belowReserve: arrival - uncertainty < reserve)
    }
}

struct TripEnergyPoint: Codable, Equatable {
    var elapsedSeconds: Double
    var distanceKm: Double?
    var predictedSOC: Double?
    var actualSOC: Double
}

struct TripEnergyChargingStop: Codable, Identifiable, Equatable {
    var id: String
    var startedAt: Date
    var endedAt: Date?
    var startSOC: Double?
    var endSOC: Double?
    var batteryAddedKWh: Double?
    var addedSOC: Double? {
        guard endedAt != nil, let startSOC, let endSOC, startSOC.isFinite, endSOC.isFinite,
              (0...100).contains(startSOC), (0...100).contains(endSOC), endSOC >= startSOC else { return nil }
        return endSOC - startSOC
    }
}

struct TripEnergyRecord: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var vin: String
    var routeKey: String
    var destination: String
    var startedAt: Date
    var startSOC: Double
    var initial: TripEnergyEstimate
    var endedAt: Date?
    var actualArrivalSOC: Double?
    var arrived = false
    var chargingObserved = false
    var startOdometerKm: Double?
    var points: [TripEnergyPoint]?
    var chargingStops: [TripEnergyChargingStop]?
    var chargingDataIncomplete: Bool?
    var unexplainedSOCGain: Bool?
    var chargingAccounted: Bool { unexplainedSOCGain != true && chargingDataIncomplete != true && (!chargingObserved || !(chargingStops ?? []).isEmpty && (chargingStops ?? []).allSatisfy { $0.addedSOC != nil }) }
    var addedSOC: Double { (chargingStops ?? []).compactMap(\.addedSOC).reduce(0, +) }
    var adjustedArrivalSOC: Double { min(100, max(0, initial.rawArrivalSOC + addedSOC)) }
    var actualUsedSOC: Double? { chargingAccounted && arrived ? actualArrivalSOC.flatMap { startSOC + addedSOC >= $0 ? startSOC + addedSOC - $0 : nil } : nil }
    var actualUsedKWh: Double? { actualUsedSOC.map { $0 / 100 * initial.capacityKWh } }
    var errorSOC: Double? { chargingAccounted && arrived ? actualArrivalSOC.map { $0 - adjustedArrivalSOC } : nil }
    func predictedSOC(distanceKm: Double, at: Date, actualSOC: Double) -> Double? {
        guard unexplainedSOCGain != true, chargingDataIncomplete != true, !chargingObserved || !(chargingStops ?? []).isEmpty else { return nil }
        var gain = 0.0
        for stop in chargingStops ?? [] where at >= stop.startedAt {
            if let end = stop.endedAt, at >= end {
                guard let added = stop.addedSOC else { return nil }; gain += added
            } else {
                guard let start = stop.startSOC, (0...100).contains(start), actualSOC >= start else { return nil }
                gain += actualSOC - start // Observed net SOC gain while stopped, never charger/grid energy.
            }
        }
        return min(100, max(0, startSOC + gain - distanceKm * initial.socPerKm))
    }
    func resumable(vin: String, now: Date) -> Bool {
        self.vin == vin && endedAt == nil && (-5...172800).contains(now.timeIntervalSince(startedAt))
    }
}
