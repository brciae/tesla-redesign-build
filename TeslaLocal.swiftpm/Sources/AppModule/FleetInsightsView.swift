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
                    Text("내 차량 분석·관리").font(.headline)
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
                    ForEach(snapshot.insightSections(), id: \.title) { section in
                        InfoCard {
                            Text(section.title).font(.headline)
                            Text(snapshot.sectionIsRecent(section.source) ? "최근 수신" : "마지막 수신 · 현재 상태와 다를 수 있음").font(.caption).foregroundStyle(Theme.muted)
                            ForEach(section.rows, id: \.label) { row in
                                HStack(alignment: .top) {
                                    Text(row.label).foregroundStyle(Theme.muted)
                                    Spacer(minLength: 12)
                                    Text(row.value).multilineTextAlignment(.trailing)
                                }.font(.subheadline)
                            }
                        }
                    }
                    InfoCard {
                        Text("기록 기반 소비 분석").font(.headline)
                        Text(model.screenBriefing(.battery, days: 30)).font(.subheadline).lineSpacing(5)
                    }
                    InfoCard {
                        Text("수신 데이터 전체 보기").font(.headline)
                        Caption("현재 응답에 포함된 필드만 표시합니다. 미수신·null은 0이나 꺼짐으로 해석하지 않습니다.")
                        ForEach(snapshot.payload.keys.sorted(), id: \.self) { key in
                            DisclosureGroup(key) {
                                ForEach(snapshot.flattenedFields(section: key), id: \.label) { row in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(row.label).font(.caption.monospaced()).foregroundStyle(Theme.muted)
                                        Text(row.value).font(.caption).textSelection(.enabled)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                                }
                            }
                        }
                    }
                    Caption("현재 화면은 Fleet 조회 응답입니다. 지속적인 Telemetry 수집 서버가 연결되지 않아 앱을 닫은 동안의 전체 주행·충전 이력을 자동 복원하지는 못합니다.")
                } else { Text("Fleet 계정과 차량을 연결한 후 조회해 주세요.").foregroundStyle(Theme.muted) }
            }.padding(16)
        }.background(Theme.bg).navigationTitle("차량 상세 데이터").navigationBarTitleDisplayMode(.inline)
    }
}
