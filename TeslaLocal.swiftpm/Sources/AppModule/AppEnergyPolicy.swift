import Foundation

enum AppEnergyPolicy {
    enum LocationMode { case guidance, standby, off }
    static func locationMode(guiding: Bool, starting: Bool, presented: Bool, visible: Bool, active: Bool) -> LocationMode {
        if guiding || starting { return .guidance }
        return presented && visible && active ? .standby : .off
    }
    static var saving: Bool {
        let enabled = (UserDefaults.standard.object(forKey: "energy.saving") as? Bool) ?? true
        if #available(iOS 15, macOS 12, *) { return enabled || ProcessInfo.processInfo.isLowPowerModeEnabled }
        return enabled
    }
    static func refreshInterval(active: Bool, guiding: Bool, charging: Bool, saving: Bool) -> TimeInterval {
        if !active { return saving ? 60 : 15 }
        return saving && !guiding && !charging ? 15 : 5
    }
}
