import Foundation

enum OwnershipAnalysis {
    struct CostComparison {
        let electric: Double
        let gasoline: Double
        var savings: Double { gasoline - electric }
    }
    static func cost(distanceKm: Double?, energyKWh: Double?, electricity: Double?, gasoline: Double?, gasolineEfficiency: Double?) -> CostComparison? {
        guard let km = distanceKm, km.isFinite, km > 0,
              let kWh = energyKWh, kWh.isFinite, kWh > 0,
              let tariff = electricity, tariff.isFinite, tariff >= 0,
              let price = gasoline, price.isFinite, price > 0,
              let efficiency = gasolineEfficiency, efficiency.isFinite, efficiency > 0 else { return nil }
        return CostComparison(electric: kWh * tariff, gasoline: km / efficiency * price)
    }
    static func change(current: Double?, previous: Double?) -> Double? {
        guard let current, let previous, current.isFinite, previous.isFinite, current > 0, previous > 0 else { return nil }
        return (current / previous - 1) * 100
    }
    static func warrantyEnd(start: Date, years: Int, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .year, value: years, to: start)
    }
    static func warrantySummary(start: Date?, years: Int, limitKm: Double?, odometerKm: Double?, now: Date = Date(), calendar: Calendar = .current) -> String {
        var parts: [String] = []
        if let start, start <= now, let end = warrantyEnd(start: start, years: years, calendar: calendar) {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: end)).day ?? 0
            parts.append(days > 0 ? "기간 \(days)일 남음" : "기간 기준 도달")
        } else { parts.append("보증 시작일 확인 필요") }
        if let limitKm {
            if let km = odometerKm, km.isFinite, km >= 0 {
                parts.append(km < limitKm ? String(format: "거리 %.0f km 남음", limitKm - km) : "거리 기준 도달")
            } else { parts.append("주행거리 미수신") }
        }
        return parts.joined(separator: " · ")
    }
}
