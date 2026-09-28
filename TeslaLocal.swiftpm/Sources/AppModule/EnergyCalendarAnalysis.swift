import Foundation
import CoreFoundation

struct EnergyCalendarDay: Identifiable {
    let date: Date
    var id: Date { date }
    var driving: Double = 0
    var parking: Double = 0
    var distance: Double = 0
    var chargeSupply: Double = 0
    var chargeVehicle: Double = 0
    var chargeMinutes: Double = 0
    var hasChargeDuration = false
    var hasUnknownChargeDuration = false
    var hasDrive = false
    var hasParking = false
    var hasSupply = false
    var hasVehicleCharge = false
}

enum EnergyCalendarAnalysis {
    static func days(month: Date, trips: [[String: Any]], parking: [[String: Any]], charges: [[String: Any]], capacityKWh: Double, calendar: Calendar = .current) -> [EnergyCalendarDay] {
        guard let interval = calendar.dateInterval(of: .month, for: month), let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        var result = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }.map { EnergyCalendarDay(date: $0) }
        func number(_ row: [String: Any], _ key: String) -> Double? {
            guard let value = row[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
            return value.doubleValue
        }
        func index(_ ms: Double?) -> Int? {
            guard let ms else { return nil }; let date = Date(timeIntervalSince1970: ms / 1000)
            guard date >= interval.start, date < interval.end else { return nil }
            return calendar.component(.day, from: date) - 1
        }
        for trip in trips where trip["duplicate"] as? Bool != true {
            guard let i = index(number(trip, "end")), let energy = number(trip, "estimatedKWh"), energy >= 0 else { continue }
            result[i].hasDrive = true; result[i].driving += energy; result[i].distance += max(0, number(trip, "distanceKm") ?? 0)
        }
        var coveredUntil: Double = -1
        for p in parking.sorted(by: { (number($0, "start") ?? 0) < (number($1, "start") ?? 0) }) where p["classification"] as? String == "parking" {
            guard let start = number(p, "start"), let end = number(p, "end"), start >= coveredUntil, end >= start,
                  let i = index(end), let soc = number(p, "deltaSOC"), (0...100).contains(soc), capacityKWh > 0 else { continue }
            let overlapsCharge = charges.filter { $0["chargeExcluded"] as? Bool != true }.contains { charge in
                guard let at = number(charge, "at") else { return false }
                let finish = number(charge, "end") ?? at + 1
                return start < finish && at < end
            }
            if overlapsCharge { continue }
            coveredUntil = end; result[i].hasParking = true; result[i].parking += soc / 100 * capacityKWh
        }
        for charge in charges where charge["chargeExcluded"] as? Bool != true {
            guard let i = index(number(charge, "at")) else { continue }
            if let value = number(charge, "supplyKWh"), value >= 0 { result[i].chargeSupply += value; result[i].hasSupply = true }
            if let value = number(charge, "vehicleReportedKWh"), value >= 0 { result[i].chargeVehicle += value; result[i].hasVehicleCharge = true }
            if charge["collectedAfterEnd"] as? Bool != true, charge["startTimeObserved"] as? Bool != false, charge["endTimeObserved"] as? Bool != false, let start = number(charge, "at"), let end = number(charge, "end"), end >= start {
                result[i].chargeMinutes += (end - start) / 60000; result[i].hasChargeDuration = true
            } else { result[i].hasUnknownChargeDuration = true }
        }
        return result
    }
}
