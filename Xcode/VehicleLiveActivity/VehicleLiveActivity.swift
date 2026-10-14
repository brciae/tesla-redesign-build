import ActivityKit
import SwiftUI
import WidgetKit

@main
struct VehicleLiveActivityBundle: WidgetBundle {
    var body: some Widget { VehicleLiveActivity() }
}

struct VehicleLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VehicleActivityAttributes.self) { context in
            VehicleActivitySummary(state: context.state, stale: context.isStale)
                .environment(\.colorScheme, .dark)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "ylcompanion://activity"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VehicleActivityIcon()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VehicleActivityCompact(state: context.state, stale: context.isStale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VehicleActivitySummary(state: context.state, stale: context.isStale)
                        .environment(\.colorScheme, .dark)
                }
            } compactLeading: {
                VehicleActivityIcon()
            } compactTrailing: {
                VehicleActivityCompact(state: context.state, stale: context.isStale)
            } minimal: {
                VehicleActivityMinimal(state: context.state, stale: context.isStale)
            }
            .widgetURL(URL(string: "ylcompanion://activity"))
            .keylineTint(.cyan)
        }
    }
}
