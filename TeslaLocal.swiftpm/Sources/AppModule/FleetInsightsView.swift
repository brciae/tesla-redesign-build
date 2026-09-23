import SwiftUI

/// Read-only analysis of the selected vehicle. No wake-up or control commands.
struct FleetInsightsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var fleet: TeslaFleetClient
    private var snapshot: FleetVehicleSnapshot? {
        guard let value = fleet.vehicleSnapshot, value.vin == fleet.selectedVin else { return nil }
        return value
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                InfoCard {
                    Text("내 차량").font(.headline)
                    NavigationLink("주행 습관·에너지·비용 비교") { DrivingInsightsView() }
                    NavigationLink("배터리 온도·전압·Telemetry 추이") { FleetTelemetryView(vin: fleet.selectedVin) }
                    NavigationLink("보증 기간·남은 거리") {
                        WarrantyGuideView(vin: fleet.selectedVin, odometerKm: snapshot?.number("vehicle_state", "odometer").map { $0 * 1.609344 })
                    }
                    ForEach(FleetSupplement.allCases) { kind in
                        NavigationLink(kind.title) { FleetSupplementView(fleet: fleet, kind: kind) }
                    }
                }
                LocalBriefingControls(title: "차량 상세 데이터", summary: { snapshot?.insightSummary() ?? ["선택 차량의 Fleet 자료가 아직 없습니다."] })
                HStack {
                    Text(fleet.vehicleReadStatus).font(.subheadline)
                    Spacer()
                    Button("새로 조회") { Task { await fleet.refreshVehicleSnapshot(force: true) } }
                        .disabled(fleet.isReadingVehicle)
                }
                if let error = fleet.vehicleReadError { Text(error).foregroundStyle(.orange).font(.caption) }
                if let snapshot {
                    ForEach(snapshot.insightSections().filter { $0.rows.contains { !$0.value.contains("미수신") } }, id: \.title) { section in
                        InfoCard {
                            Text(section.title).font(.headline)
                            Text(snapshot.sectionIsRecent(section.source) ? "최근 수신" : "마지막 수신 · 현재 상태와 다를 수 있음").font(.caption).foregroundStyle(Theme.muted)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16) {
                                ForEach(section.rows.filter { !$0.value.contains("미수신") }, id: \.label) { row in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(row.label).font(.caption).foregroundStyle(Theme.muted)
                                        Text(row.value).font(.title3.weight(.semibold)).minimumScaleFactor(0.7)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                } else { Text("Fleet 계정과 차량을 연결한 후 조회해 주세요.").foregroundStyle(Theme.muted) }
            }.padding(16)
        }.background(Theme.bg).navigationTitle("차량 관리").navigationBarTitleDisplayMode(.inline)
    }
}
