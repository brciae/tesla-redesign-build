import Foundation

/// AVKit start/stop callbacks may arrive after the guide that requested them ended.
struct NavigationPipLifecycle {
    private(set) var wanted = false
    private(set) var starting = false
    private(set) var active = false
    private(set) var stopping = false
    mutating func setWanted(_ value: Bool) { wanted = value }
    mutating func requestStart() -> Bool {
        guard wanted, !starting, !active, !stopping else { return false }
        starting = true; return true
    }
    mutating func willStart() -> Bool {
        guard wanted, !stopping else { stopping = true; return false }
        starting = true; return true
    }
    mutating func didStart() -> Bool {
        starting = false; active = true
        guard wanted, !stopping else { stopping = true; return false }
        return true
    }
    @discardableResult mutating func end() -> Bool {
        wanted = false
        stopping = starting || active || stopping
        return stopping
    }
    mutating func didStop() { starting = false; active = false; stopping = false }
}
