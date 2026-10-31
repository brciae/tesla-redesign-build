#if DEBUG
import SwiftUI
/// Simulator-only entry points use the production model and production views, with demo data.
struct ProductionReviewRoot: View {
    @ObservedObject var model: AppModel
    @State private var healthPrepared = false
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
                case "climate": TeslaInteractiveClimateView(link: model.link).navigationTitle("실내 공조").navigationBarTitleDisplayMode(.inline)
                case "parking": ScrollView { SmartParkingCard(link: model.link).padding() }.navigationTitle("주차 기록").navigationBarTitleDisplayMode(.inline)
                case "menu": MenuTabRootView(link: model.link, navigation: model.navigation)
                default: Text("Unknown review screen")
                }
            } }
        }.environmentObject(model)
        .onAppear {
            if screen == "batterySummary", !healthPrepared {
                healthPrepared = true
                do {
                    var state = try model.runtime.call("export") as? Object ?? [:]
                    let now = Date().timeIntervalSince1970 * 1000
                    state["charges"] = [84.9, 84.8, 84.7, 84.7, 84.7].enumerated().map { i, capacity -> Object in
                        let at = now - Double(6 - i) * 86400000
                        return ["id": "review-capacity-\(i)", "at": at, "end": at + 3600000, "startSOC": 30, "endSOC": 80,
                                "vehicleReportedKWh": capacity * 0.5, "complete": true, "startSOCObserved": true,
                                "endSOCObserved": true, "source": "manual", "chargeReviewConfirmed": true]
                    }
                    model.output = try model.runtime.call("load", ["state": state]) as? Object ?? [:]
                } catch { model.errorMessage = error.localizedDescription }
            }
            if screen == "parking" {
                var record = SmartParkingRecord()
                record.timestamp = Date().addingTimeInterval(-3600)
                record.mobile.buildingName = "검증용 주차장"
                record.mobile.address = "예시 주차 위치"
                record.mobile.mobileLatitude = 37.5; record.mobile.mobileLongitude = 127
                SmartParkingManager.shared.latestRecord = record
            }
        }
    }
}
#endif
