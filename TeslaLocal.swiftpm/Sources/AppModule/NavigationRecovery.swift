import Foundation

/// Only an active destination is retained; never reuse an old phone position as a new origin.
struct NavigationRecoveryCheckpoint: Codable, Equatable {
    var vin: String
    var name: String
    var latitude: Double
    var longitude: Double
    var manual: Bool
    var savedAt: Date
    func usable(vin selectedVIN: String, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(savedAt)
        return vin == selectedVIN && !name.isEmpty && latitude.isFinite && longitude.isFinite &&
            abs(latitude) <= 90 && abs(longitude) <= 180 && !(latitude == 0 && longitude == 0) && age >= -5 && age <= 21600
    }
}
