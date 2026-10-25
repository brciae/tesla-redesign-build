import Foundation
@main struct NavigationPipLifecycleTests {
    static func main() {
        var p = NavigationPipLifecycle()
        p.setWanted(true)
        precondition(p.requestStart())
        precondition(!p.requestStart(), "duplicate background/manual start is suppressed")
        precondition(p.end(), "stop is required even before AVKit marks PiP active")
        precondition(!p.willStart(), "late willStart must be rejected after end")
        precondition(!p.didStart(), "late didStart must request immediate stop")
        p.setWanted(true)
        precondition(!p.requestStart(), "new guidance cannot overlap old pending stop")
        p.didStop()
        precondition(p.requestStart() && p.willStart() && p.didStart())
        precondition(p.active)
        precondition(p.end()); p.didStop()
        precondition(!p.active && !p.starting && !p.stopping)
        precondition(!p.willStart(), "automatic inline start after guide end must also be rejected")
        p.didStop(); p.setWanted(true)
        precondition(p.willStart() && p.didStart(), "normal OS automatic start remains supported")
        print("PASS: pending PiP stop, late callbacks, duplicate starts, new-guide isolation and automatic inline lifecycle")
    }
}
