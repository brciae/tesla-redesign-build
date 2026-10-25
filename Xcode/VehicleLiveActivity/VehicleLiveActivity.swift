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
            Group {
                if context.state.guiding {
                    VehicleNavigationCard(state: context.state, stale: context.isStale)
                } else {
                    VehicleActivitySummary(state: context.state, stale: context.isStale)
                        .foregroundStyle(.black)
                }
            }
                .environment(\.colorScheme, .light)
                .activityBackgroundTint(.white.opacity(0.92))
                .activitySystemActionForegroundColor(.black)
                .widgetURL(URL(string: context.state.guiding ? "ylcompanion://activity" : context.state.charging ? "ylcompanion://charging" : "ylcompanion://activity"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VehicleActivityIcon()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VehicleActivityCompact(state: context.state, stale: context.isStale)
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Group {
                        if context.state.guiding {
                            VehicleNavigationCard(state: context.state, stale: context.isStale)
                                .background(.white, in: RoundedRectangle(cornerRadius: 18))
                        } else {
                            VehicleActivitySummary(state: context.state, stale: context.isStale)
                                .foregroundStyle(.white).environment(\.colorScheme, .dark)
                        }
                    }
                }
            } compactLeading: {
                VehicleActivityIcon()
            } compactTrailing: {
                VehicleActivityCompact(state: context.state, stale: context.isStale)
                    .foregroundStyle(.white)
            } minimal: {
                VehicleActivityMinimal(state: context.state, stale: context.isStale)
            }
            .widgetURL(URL(string: context.state.guiding ? "ylcompanion://activity" : context.state.charging ? "ylcompanion://charging" : "ylcompanion://activity"))
            .keylineTint(.cyan)
        }
    }
}
