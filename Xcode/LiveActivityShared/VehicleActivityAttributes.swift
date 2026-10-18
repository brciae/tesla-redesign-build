import ActivityKit
import Foundation

struct VehicleActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var connected: Bool
        var guiding: Bool
        var destination: String
        var instruction: String
        var remainingMinutes: Int?
        var batteryPercent: Int?
        var observedAt: Date
        var turnSymbol: String? = nil
        var turnMetres: Int? = nil
        var arrivalAt: Date? = nil
        var exitClock: Int? = nil
        var chargeStatus: String? = nil
        var chargeObservedAt: Date? = nil
        var chargeLimit: Int? = nil
        var chargerKW: Double? = nil
        var chargeRemainingMinutes: Int? = nil

        var charging: Bool { chargeStatus == "Charging" }
        var chargingStale: Bool {
            guard let at = chargeObservedAt else { return true }
            return !(-5...120).contains(Date().timeIntervalSince(at))
        }
    }
    var name: String = "YL Companion"
}
