import Foundation

@main struct EnergyCalendarTests {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 13))!
        let start = day.timeIntervalSince1970 * 1000
        let valid: [String: Any] = ["at": start, "end": start + 3600000, "vehicleReportedKWh": 40.36, "supplyKWh": 43.1, "startTimeObserved": true, "endTimeObserved": true]
        var duplicates = (0..<35).map { i -> [String: Any] in
            ["at": start + Double(i) * 60000, "end": start + Double(i) * 60000, "vehicleReportedKWh": 40.36, "supplyKWh": 43.1, "chargeExcluded": true]
        }
        duplicates.append(valid)
        let days = EnergyCalendarAnalysis.days(month: day, trips: [], parking: [], charges: duplicates, capacityKWh: 75, calendar: calendar)
        precondition(abs(days[26].chargeVehicle - 40.36) < 0.001)
        precondition(abs(days[26].chargeTotal - 40.36) < 0.001)
        precondition(abs(days[26].chargeSupply - 43.1) < 0.001)
        precondition(days[26].chargeMinutes == 60)
        precondition(days[26].hasChargeDuration && !days[26].hasUnknownChargeDuration)
        var unknown = valid; unknown["collectedAfterEnd"] = true; unknown["startTimeObserved"] = false
        let partial = EnergyCalendarAnalysis.days(month: day, trips: [], parking: [], charges: [unknown], capacityKWh: 75, calendar: calendar)
        precondition(partial[26].chargeMinutes == 0, "Collection timestamps are not charging duration")
        precondition(!partial[26].hasChargeDuration && partial[26].hasUnknownChargeDuration)
        let mixed: [[String: Any]] = [valid,
            ["at": start, "supplyKWh": 12.0],
            ["at": start, "estimatedStoredKWh": 5.0, "supplyKWh": 6.0],
            ["at": start, "nasSupplyKWh": 3.0],
            ["at": start, "vehicleReportedKWh": -1.0, "supplyKWh": 2.0]]
        let combined = EnergyCalendarAnalysis.days(month: day, trips: [], parking: [], charges: mixed, capacityKWh: 75, calendar: calendar)
        precondition(abs(combined[26].chargeTotal - 45.36) < 0.001, "Grid supply must never inflate battery charging energy")
        print("PASS: calendar excludes duplicate energy/time and never invents duration from collection times")
    }
}
