import Foundation
@main struct EnergyPolicyTests {
    static func main() {
        for active in [false, true] { for shown in [false, true] {
            precondition(AppEnergyPolicy.locationMode(guiding: true, starting: false, presented: shown, visible: false, active: active) == .guidance, "Lock/call/hidden UI must not stop active guidance")
            precondition(AppEnergyPolicy.locationMode(guiding: false, starting: true, presented: shown, visible: false, active: active) == .guidance)
        } }
        precondition(AppEnergyPolicy.locationMode(guiding: false, starting: false, presented: true, visible: true, active: true) == .standby)
        for mode in [(false,true,true),(true,false,true),(true,true,false)] {
            precondition(AppEnergyPolicy.locationMode(guiding: false, starting: false, presented: mode.0, visible: mode.1, active: mode.2) == .off)
        }
        precondition(AppEnergyPolicy.refreshInterval(active: false, guiding: true, charging: true, saving: true) == 60)
        precondition(AppEnergyPolicy.refreshInterval(active: true, guiding: false, charging: false, saving: true) == 15)
        precondition(AppEnergyPolicy.refreshInterval(active: true, guiding: true, charging: false, saving: true) == 5)
        precondition(AppEnergyPolicy.refreshInterval(active: true, guiding: false, charging: true, saving: true) == 5)
        print("PASS: energy policy keeps guidance across lock/calls and stops hidden standby GPS; idle refresh bounded")
    }
}
