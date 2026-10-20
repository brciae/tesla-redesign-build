import Foundation

enum VehicleActivitySessionPolicy {
    static func shouldEnd(connected: Bool, guiding: Bool, previouslyGuiding: Bool, observationAge: TimeInterval,
                          charging: Bool = false, previouslyCharging: Bool = false) -> Bool {
        // A Bluetooth connection alone is not an ongoing user activity.
        return !guiding && !charging
    }
}
