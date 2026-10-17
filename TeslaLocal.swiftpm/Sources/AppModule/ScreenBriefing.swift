import SwiftUI

/// Read-only, explicit playback: never dispatches a vehicle or automation command.
struct ScreenBriefingControls: View {
    let scope: BriefingScope
    var compact = false
    var text: (() async -> String)? = nil
    var body: some View {
        EmptyView()
    }
}
