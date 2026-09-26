import SwiftUI
import Charts

/// Visual overview of the selected vehicle; readings never authorize commands.
struct FleetInsightsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var fleet: TeslaFleetClient
    private var snapshot: FleetVehicleSnapshot? {
        guard let value = fleet.vehicleSnapshot, value.vin == fleet.selectedVin else { return nil }
        return value
    }
    private var charges: [Object] { Array(model.output.object("charging").rows("rows").prefix(14).reversed()) }
    private var chartDayStride: Int {
        let times = charges.compactMap { $0.number("at") }
        guard let first = times.min(), let last = times.max() else { return 1 }
        return max(1, Int(ceil((last - first) / 86_400_000 / 4)))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("내 차량").font(.title.bold())
                        Text(model.settings.string("model", "Model Y L")).font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button { Task { await fleet.refreshVehicleSnapshot(force: true) } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }.disabled(fleet.isReadingVehicle)
                }
                if let error = fleet.vehicleReadError { Text(error).font(.caption).foregroundStyle(.orange) }
                InfoCard {
                    HStack(spacing: 28) {
                        if let soc = snapshot?.soc {
                            Gauge(value: soc, in: 0...100) { Image(systemName: "bolt.fill") } currentValueLabel: { Text(String(format: "%.0f%%", soc)).font(.headline) }
                                .gaugeStyle(.accessoryCircularCapacity).tint(.mint).scaleEffect(1.35).frame(width: 90, height: 100)
                        }
                        VStack(alignment: .leading, spacing: 9) {
                            if let km = snapshot?.rangeKm { Text(String(format: "%.0f km", km)).font(.largeTitle.bold()); Text("주행 가능 거리").font(.caption).foregroundStyle(Theme.muted) }
                            if let odo = model.displayOdometerKm { Label(String(format: "누적 %.0f km", odo), systemImage: "speedometer").font(.subheadline) }
                            if snapshot?.charging == true { Label("충전 중", systemImage: "bolt.fill").foregroundStyle(.mint) }
                        }
                        Spacer(minLength: 0)
                    }
                    if !model.vehicleReference.isEmpty { Text("차량 사양·참고 기록 " + model.vehicleReference.string("sourceDate")).font(.caption2).foregroundStyle(Theme.muted) }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    NavigationLink { CareView() } label: { destination("타이어·정비", "tirepressure", .cyan) }
                    NavigationLink { WarrantyGuideView(vin: fleet.selectedVin, odometerKm: model.displayOdometerKm, vehicleReference: model.vehicleReference) } label: { destination("보증·관리", "checkmark.shield.fill", .purple) }
                }.buttonStyle(.plain)
                if !model.vehicleReference.isEmpty {
                    InfoCard {
                        Label("배터리 사양", systemImage: "battery.100percent").font(.headline)
                        HStack {
                            spec(model.vehicleReference.number("nominalKWh"), unit: "kWh", label: "명목 에너지")
                            Spacer()
                            Text(model.vehicleReference.string("chemistry")).font(.title.bold()).foregroundStyle(.mint)
                            Text(model.vehicleReference.string("cellMaker")).font(.caption)
                        }
                        Text("명목 사양 · 사용 가능 용량과 구분").font(.caption2).foregroundStyle(Theme.muted)
                    }
                }
                DisclosureGroup("차량 상태 상세") {
                    if let snapshot {
                        ForEach(snapshot.insightSections().filter { $0.title != "타이어 상태" }, id: \.title) { section in
                            let rows = section.rows.filter { !$0.value.contains("미수신") }
                            if !rows.isEmpty {
                                InfoCard {
                                    Text(section.title).font(.headline)
                                    ForEach(rows, id: \.label) { row in HStack { Text(row.label).foregroundStyle(Theme.muted); Spacer(); Text(row.value) }.font(.subheadline) }
                                }
                            }
                        }
                    }
                }
                DisclosureGroup("충전소·서비스·업데이트") {
                    ForEach(FleetSupplement.allCases.filter { $0 != .telemetryConfig && $0 != .telemetryErrors }) { kind in NavigationLink(kind.title) { FleetSupplementView(fleet: fleet, kind: kind) }.padding(.vertical, 8) }
                }
                LocalBriefingControls(title: "차량 상태", summary: { snapshot?.insightSummary() ?? [] })
                Text(fleet.vehicleReadStatus).font(.caption2).foregroundStyle(Theme.muted)
            }.padding(16)
        }.background(Theme.bg).navigationTitle("차량 관리").navigationBarTitleDisplayMode(.inline)
    }
    private func destination(_ title: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) { Image(systemName: icon).font(.title2).foregroundStyle(color); Text(title).font(.subheadline.bold()) }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }
    private func spec(_ value: Double?, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(value.map { String(format: unit == "원" ? "%.0f %@" : "%.1f %@", $0, unit) } ?? "—").font(.title3.bold()); Text(label).font(.caption2).foregroundStyle(Theme.muted) }
    }
}
