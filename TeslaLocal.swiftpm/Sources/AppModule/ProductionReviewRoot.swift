#if DEBUG
import SwiftUI
/// Simulator-only entry points use the production model and production views, with demo data.
struct ProductionReviewRoot: View {
    @ObservedObject var model: AppModel
    private var screen: String { let args = ProcessInfo.processInfo.arguments; guard let i = args.firstIndex(of: "--ui-review-screen"), i + 1 < args.count else { return "home" }; return args[i + 1] }
    var body: some View {
        Group {
            if screen == "home" { MainView(model: model, link: model.link, navigation: model.navigation) }
            else { NavigationStack {
                switch screen {
                case "automation": AutomationView()
                case "tariffs": ChargeTimeOfUseView()
                case "launch": BrandLaunchArtwork()
                case "coverage": RecordCoverageView()
                case "month": MonthClosingView()
                case "battery": BatteryEvidenceView()
                case "health": CompanionHealthView(link: model.link, voice: model.voice)
                case "navigation": Form { NavigationDisplaySettings(navigation: model.navigation) }
                default: Text("Unknown review screen")
                }
            } }
        }.environmentObject(model)
    }
}
#endif
