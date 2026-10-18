import Foundation

enum VehicleActivitySessionPolicy {
    static func shouldEnd(connected: Bool, guiding: Bool, previouslyGuiding: Bool, observationAge: TimeInterval,
                          charging: Bool = false, previouslyCharging: Bool = false) -> Bool {
        guard !connected, !guiding, !charging else { return false }
        // Phone-only guidance must end immediately. Preserve the existing reconnect grace
        // for a vehicle activity; background reconnection cannot start a new activity.
        return previouslyGuiding || previouslyCharging || !observationAge.isFinite || observationAge > 90
    }
}
