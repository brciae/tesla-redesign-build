import SwiftUI
import Charts
import UniformTypeIdentifiers

struct FleetTelemetryView: View {
    let vin: String
    @ObservedObject private var store = FleetTelemetryStore.shared
    @State private var importing = false
    @State private var error = ""
    @State private var search = ""
    @State private var selectedField = "ModuleTempMax"
    private var latest: [String: FleetTelemetryReading] { store.latest(vin: vin) }
    private var trend: [FleetTelemetryReading] { Array(store.records.filter { $0.vin == vin && $0.field == selectedField && !$0.invalid && $0.number != nil }.suffix(240)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                InfoCard {
                    Text("배터리·차량 심층 분석").font(.headline)
                    Caption("차량의 스트리밍 원본 값과 시각을 보존합니다. 현재 Fleet 조회와 별도이며, 수집 서버 연결 전에는 미수신으로 표시합니다.")
                    Text(store.status).font(.caption)
                    Button("Telemetry 기록 가져오기") { importing = true }.disabled(vin.isEmpty)
                    if !error.isEmpty { Caption(error) }
                }
                InfoCard {
                    Text("배터리 열관리·전기 상태").font(.headline)
                    measurement("최저 모듈 온도", field: "ModuleTempMin", unit: "°C")
                    measurement("최고 모듈 온도", field: "ModuleTempMax", unit: "°C")
                    difference("모듈 온도 편차", high: "ModuleTempMax", low: "ModuleTempMin", unit: "°C", scale: 1)
                    difference("셀 블록 전압 편차", high: "BrickVoltageMax", low: "BrickVoltageMin", unit: "mV", scale: 1000)
                    measurement("배터리 팩 전압", field: "PackVoltage", unit: "V")
                    measurement("배터리 팩 전류", field: "PackCurrent", unit: "A")
                    measurement("남은 에너지", field: "EnergyRemaining", unit: "kWh")
                    measurement("차량 보고 완충 에너지", field: "NominalFullPackEnergyKwh", unit: "kWh")
                    Caption("온도·전압 편차는 2초 이내 같은 시각의 유효한 값끼리 비교합니다. 이 값만으로 배터리 결함이나 열화를 판정하지 않습니다.")
                }
                InfoCard {
                    Text("기록 추이").font(.headline)
                    Picker("추이 항목", selection: $selectedField) {
                        Text("최고 온도 °C").tag("ModuleTempMax")
                        Text("배터리 %").tag("Soc")
                        Text("충전 전력 kW").tag("DCChargingPower")
                    }.pickerStyle(.menu)
                    if trend.count > 1 {
                        Chart(trend) { point in
                            PointMark(x: .value("시각", point.at), y: .value("수신값", point.number!)).foregroundStyle(.mint)
                        }.frame(height: 180)
                        Caption("최근 유효 표본 최대 240개 · 미수신 구간은 연결하지 않습니다.")
                    } else { Caption("시계열 표본이 쌓이면 온도·잔량·충전 추이를 표시합니다.") }
                }
                InfoCard {
                    Text("모든 수신 신호").font(.headline)
                    TextField("필드 이름 검색", text: $search).textFieldStyle(.roundedBorder)
                    ForEach(latest.keys.sorted().filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { field in
                        if let value = latest[field] {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(field).font(.subheadline.bold())
                                Text(value.text).font(.caption.monospaced()).textSelection(.enabled)
                                Text(value.at.formatted(date: .abbreviated, time: .standard)).font(.caption2).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    if latest.isEmpty { Caption("수신 기록 없음") }
                }
            }.padding(16)
        }.background(Theme.bg).navigationTitle("배터리·Telemetry")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 5_000_000 else { throw FleetTelemetryData.failure("최대 5 MB 파일을 가져올 수 있습니다.") }
                try store.ingest(Data(contentsOf: url), vin: vin); error = ""
            } catch { self.error = error.localizedDescription }
        }
    }
    private func measurement(_ title: String, field: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(title); Spacer(); Text(latest[field].flatMap { $0.invalid ? nil : $0.number }.map { String(format: "%.1f %@", $0, unit) } ?? "미수신") }.font(.subheadline)
            if let value = latest[field] { Text("원본 시각 " + value.at.formatted(date: .abbreviated, time: .standard)).font(.caption2).foregroundStyle(Theme.muted) }
        }
    }
    private func difference(_ title: String, high: String, low: String, unit: String, scale: Double) -> some View {
        HStack { Text(title); Spacer(); Text(FleetTelemetryData.pairedDifference(latest[high], latest[low]).map { String(format: "%.1f %@", $0 * scale, unit) } ?? "동시 표본 없음") }.font(.subheadline)
    }
}
