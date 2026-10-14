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
    }
    var name: String = "YL Companion"
}
