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
        precondition(abs(combined[26].chargeTotal - 40.36) < 0.001, "Estimated kWh and grid supply must never enter measured battery charging energy")
        let actual: [[String: Any]] = [["at": start, "vehicleReportedKWh": 86.5, "startSOC": 21.7, "endSOC": 100.0, "startSOCObserved": true, "endSOCObserved": true]]
        let observed = EnergyCalendarAnalysis.days(month: day, trips: [], parking: [], charges: actual, capacityKWh: 84.8, calendar: calendar)[26]
        precondition(observed.chargeTotal == 86.5 && abs(observed.chargeSOCAdded - 78.3) < 0.001, "SOC is observed independently of kWh/capacity; never fabricate102%")
        var estimatedSOC = actual[0]; estimatedSOC["startSOCEstimated"] = true
        precondition(EnergyCalendarAnalysis.days(month: day, trips: [], parking: [], charges: [estimatedSOC], capacityKWh: 84.8, calendar: calendar)[26].chargeSOCCount == 0)
        let repeated = EnergyCalendarAnalysis.days(month: day, trips: [], parking: [], charges: actual + actual, capacityKWh: 84.8, calendar: calendar)[26]
        precondition(abs(repeated.chargeSOCAdded - 156.6) < 0.001, "A day may contain multiple sessions; SOC addition is percentage points, never capped")
        print("PASS: calendar excludes duplicate energy/time and never invents duration from collection times")
    }
}
