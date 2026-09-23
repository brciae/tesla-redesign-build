import Foundation

struct FleetParkingBucket: Identifiable {
    let id: String
    var seconds: Double = 0
    var measuredKWh: Double = 0
    var energySeconds: Double = 0
    var title: String {
        switch id {
        case "sentry": return "감시 모드 작동 구간"
        case "climate": return "공조 작동 구간"
        case "combined": return "감시 모드·공조 동시 작동"
        case "standby": return "대기 구간"
        default: return "주차 중 자연방전"
        }
    }
}

enum FleetParkingAnalysis {
    /// Classifies observed time, not a guessed allocation of feature-specific watts.
    /// Boundaries and energy counters must be fresh, with no gaps longer than two minutes.
    static func buckets(_ records: [FleetTelemetryReading], vin: String, from: Date, to: Date) -> [FleetParkingBucket] {
        let selected = records.filter { $0.vin == vin && $0.at >= from && $0.at <= to }
        let groups = Dictionary(grouping: selected, by: \.at)
        let dates = groups.keys.sorted()
        var latest: [String: FleetTelemetryReading] = [:]
        var buckets: [String: FleetParkingBucket] = [:]
        var previous: (at: Date, category: String, energy: Double?)?
        func current(_ field: String, at: Date) -> FleetTelemetryReading? {
            guard let value = latest[field], !value.invalid, at.timeIntervalSince(value.at) <= 120 else { return nil }
            return value
        }
        func scalar(_ reading: FleetTelemetryReading?) -> String? {
            guard let reading, let data = reading.text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let raw = object.values.first else { return nil }
            return String(describing: raw).lowercased()
        }
        func state(_ reading: FleetTelemetryReading?) -> Bool? {
            guard let value = scalar(reading) else { return nil }
            if ["false", "0", "off"].contains(value) || value.hasSuffix("off") { return false }
            if ["true", "1", "on"].contains(value) || value.hasSuffix("on") || value.contains("armed") || value.contains("aware") || value.contains("panic") { return true }
            return nil
        }
        for date in dates {
            for item in groups[date] ?? [] { latest[item.field] = item }
            let gear = scalar(current("Gear", at: date))
            guard gear == "p" || gear == "shiftstatep" else { previous = nil; continue }
            let charging = scalar(current("ChargeState", at: date))
            let detail = scalar(current("DetailedChargeState", at: date))
            guard charging == "stopped" || charging == "complete" || charging == "disconnected" || charging == "nopower" || detail?.hasSuffix("stopped") == true || detail?.hasSuffix("complete") == true || detail?.hasSuffix("disconnected") == true else { previous = nil; continue }
            let sentry = state(current("SentryMode", at: date)), climate = state(current("HvacPower", at: date))
            let category: String
            switch (sentry, climate) {
            case (true?, true?): category = "combined"
            case (true?, false?): category = "sentry"
            case (false?, true?): category = "climate"
            case (false?, false?): category = "standby"
            default: category = "natural"
            }
            let energy = current("LifetimeEnergyUsed", at: date).flatMap { abs($0.at.timeIntervalSince(date)) <= 2 ? $0.number : nil }
            if let p = previous {
                let interval = date.timeIntervalSince(p.at)
                if interval > 0, interval <= 120, p.category == category {
                    var bucket = buckets[category] ?? FleetParkingBucket(id: category)
                    bucket.seconds += interval
                    if let before = p.energy, let after = energy, after >= before, after - before <= interval / 3600 * 50 {
                        bucket.measuredKWh += after - before; bucket.energySeconds += interval
                    }
                    buckets[category] = bucket
                }
            }
            previous = (date, category, energy)
        }
        return ["sentry", "climate", "combined", "standby", "natural"].compactMap { buckets[$0] }
    }
}
