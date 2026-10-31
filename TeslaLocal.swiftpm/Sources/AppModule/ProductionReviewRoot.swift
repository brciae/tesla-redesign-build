#if DEBUG
import SwiftUI
/// Simulator-only entry points use the production model and production views, with demo data.
struct ProductionReviewRoot: View {
    @ObservedObject var model: AppModel
    private var screen: String { let args = ProcessInfo.processInfo.arguments; guard let i = args.firstIndex(of: "--ui-review-screen"), i + 1 < args.count else { return "home" }; return args[i + 1] }
    var body: some View {
        Group {
            if screen == "home" { MainView(model: model, link: model.link, navigation: model.navigation) }
            else if screen == "driving" || screen == "focus" { DrivingWorkspace(navigation: model.navigation, link: model.link).environment(\.colorScheme, .dark) }
            else { NavigationStack {
                switch screen {
                case "import": TeslaExportImportView(reviewText: "StartTime,StoredKWh,Energy,Amount,Currency,Location\n2026-10-30T12:00:00Z,20,,1200,KRW,검증 충전소 A\n2026-10-30T14:00:00Z,,25,9.99,USD,검증 충전소 B")
                case "importInvalid": TeslaExportImportView(reviewText: "StartTime,StoredKWh,Amount,Currency\n2026-10-30T12:00:00Z,\"12,5\",1000,KRW")
                case "automation": AutomationView()
                case "voice": PreferencesView()
                case "tariffs": ChargeTimeOfUseView()
                case "launch": BrandLaunchArtwork()
                case "coverage": RecordCoverageView()
                case "month": MonthClosingView()
                case "battery": BatteryEvidenceView()
                case "health": CompanionHealthView(link: model.link, voice: model.voice)
                case "navigation": NavigationSetupView(navigation: model.navigation)
                case "batterySummary": BatteryView()
                case "menu": MenuTabRootView(link: model.link, navigation: model.navigation).modifier(AppDestinations(link: model.link, navigation: model.navigation))
                default: Text("Unknown review screen")
                }
            } }
        }.environmentObject(model)
    }
}
#endif
