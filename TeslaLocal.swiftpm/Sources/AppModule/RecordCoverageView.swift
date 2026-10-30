import SwiftUI

struct RecordCoverageView: View {
    @EnvironmentObject private var model: AppModel
    private var readings: [FleetTelemetryReading] { model.archiveReadings.filter { $0.vin == model.fleet.selectedVin } }
    var body: some View {
        let end = Date()
        let hours = (0..<24).map { offset in
            let start = Calendar.current.date(byAdding: .hour, value: offset - 23, to: Calendar.current.dateInterval(of: .hour, for: end)!.start)!
            return (start, readings.filter { $0.at >= start && $0.at < start.addingTimeInterval(3600) && $0.at <= end })
        }
        List {
            Section {
                Caption("앱에 보관된 NAS 자료의 시간별 관측임. 미관측은 차량 휴면·설정 간격·서버 지연·앱 동기화 등 원인이 구분되지 않은 상태이며, 고장이나 실제 데이터 손실을 확정하지 않음.").font(.caption)
                Text("BLE 수신 전체와 서버 원본 전체의 가동률을 나타내지 않음. 다른 화면의 완료 주행·충전 회수와도 집계 단위가 다름.").font(.caption)
                if model.demo { Text("예시 모드 · 실제 수집 상태가 아님").foregroundStyle(.orange) }
            }
            Section("최근 24시간 · 현재 시각까지") {
                ForEach(hours, id: \.0) { start, rows in
                    HStack {
                        Text(start, format: .dateTime.month().day().hour())
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(rows.isEmpty ? "미관측" : "관측 \(rows.count)건")
                            if !rows.isEmpty { Text("유효 \(rows.filter { !$0.invalid }.count) · 무효 \(rows.filter(\.invalid).count)").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }.navigationTitle("수집 관측")
    }
}
