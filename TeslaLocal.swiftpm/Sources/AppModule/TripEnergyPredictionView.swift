import SwiftUI
import Charts

struct TripEnergyPredictionRow: View {
    let estimate: TripEnergyEstimate
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "battery.75percent")
                Text(estimate.insufficient ? "도착 전 배터리 부족 예상" : String(format: "도착 예상 %.1f%% · %.0f–%.0f%%", estimate.arrivalSOC, estimate.lowSOC, estimate.highSOC))
                    .fontWeight(.semibold).accessibilityIdentifier("energy.forecast.arrival")
            }.foregroundStyle(estimate.belowReserve ? Color.orange : Color.primary)
            HStack(spacing: 6) {
                Text(String(format: "남은 소비 약 %.1f kWh", estimate.remainingKWh))
                    .accessibilityIdentifier("energy.forecast.consumption")
                InfoNote("예측 근거", estimate.basis + " · " + (estimate.capacityAssumed ? "가정 용량으로 kWh 환산. 범위는 참고 추정값." : "관측 용량으로 kWh 환산. 범위는 참고 추정값."))
            }
            if estimate.belowReserve { Text("예비 잔량 미달 예상 · 충전 검토").font(.system(size: 11)).foregroundStyle(.orange) }
        }.font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(.black).background(.white.opacity(0.90), in: RoundedRectangle(cornerRadius: 10))
            .environment(\.colorScheme, .light).accessibilityElement(children: .contain)
    }
}

struct TripEnergyHistoryView: View {
    @ObservedObject private var store = TripEnergyStore.shared
    let vin: String
    var body: some View {
        let rows = store.history(vin: vin)
        VStack(alignment: .leading, spacing: 12) {
            Text("경로별 에너지 예측 비교").font(.headline)
            let errors = rows.compactMap(\.errorSOC).filter(\.isFinite)
            if !errors.isEmpty {
                let meanAbsolute = errors.map { abs($0) }.reduce(0, +) / Double(errors.count)
                let bias = errors.reduce(0, +) / Double(errors.count)
                Text(String(format: "도착 비교 %d회 · 평균 절대오차 %.1f%%p · 실제−예측 %+.1f%%p", errors.count, meanAbsolute, bias)).font(.subheadline).monospacedDigit()
                Text("출발 시 저장한 예측 기준임. 도착 미수신·취소·충전량 미확인은 제외하며 다른 앱과의 정확도 우위를 뜻하지 않음.").font(.caption).foregroundStyle(.secondary)
            }
            if rows.isEmpty { Text("길안내 시작 시 예측을 저장하고, 도착 후 실제 잔량과 비교함.").font(.caption).foregroundStyle(.secondary) }
            else {
                ForEach(Array(rows.prefix(5))) { row in TripEnergyRecordView(record: row) }
                if rows.count > 5 { DisclosureGroup("이전 \(rows.count - 5)회 보기") { ForEach(Array(rows.dropFirst(5))) { row in TripEnergyRecordView(record: row) } } }
            }
            Caption("기온·바람·고도·정체를 각각 모델링한 값은 아님. 중간 충전은 관측 충전량으로 보정하며, 충전량 미확인·안내 취소·도착 잔량 미수신은 오차 비교에서 제외함.")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(14).background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct TripEnergyRecordView: View {
    let record: TripEnergyRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(record.destination).font(.subheadline.bold()); Spacer(); Text(record.startedAt, format: .dateTime.month().day().hour().minute()).font(.caption2) }
            Text(String(format: "최초 도착 예측 %.0f%% · 실제 %@", record.initial.arrivalSOC,
                        record.actualArrivalSOC.map { String(format: "%.0f%%", $0) } ?? "미수신"))
                .font(.caption).accessibilityIdentifier("energy.forecast.comparison")
            if record.chargingObserved {
                Text(record.chargingAccounted ? String(format: "중간 충전 +%.1f%%p · 충전 반영 도착 예측 %.0f%%", record.addedSOC, record.adjustedArrivalSOC) : "중간 충전 관측 · 충전량 미확인")
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("energy.forecast.charging")
                ForEach(Array((record.chargingStops ?? []).prefix(3))) { stop in
                    Text("충전 \(stop.startedAt.formatted(date: .omitted, time: .shortened)) · " + (stop.batteryAddedKWh.map { String(format: "배터리 수신 %.1f kWh", $0) } ?? "배터리 충전량 미수신"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let error = record.errorSOC, let used = record.actualUsedSOC {
                Text(String(format: "잔량 사용 %.1f%%p · 예측 차이 %+.1f%%p", used, error)).font(.caption).foregroundStyle(.secondary)
                if let kwh = record.actualUsedKWh { Text(String(format: "예상 소비 %.1f kWh · 실제 잔량 환산 %.1f kWh%@", record.initial.remainingKWh, kwh, record.initial.capacityAssumed ? " (가정 용량)" : "")).font(.caption2).foregroundStyle(.secondary) }
            } else { Text(record.unexplainedSOCGain == true ? "충전 신호 없는 잔량 증가 · BMS 보정 등 원인 미확인" : record.chargingObserved && !record.chargingAccounted ? "충전량 미확인 · 소비 합계·오차 비교 보류" : record.arrived ? "도착 잔량 미수신 · 비교 제외" : "안내 취소·목적지 변경 · 비교 제외").font(.caption).foregroundStyle(.secondary) }
            if let points = record.points, points.count >= 2 {
                TripEnergyTrendChart(points: points, mixedCharging: !record.chargingAccounted, hasCharging: record.chargingObserved)
            } else { Text("주행 중 비교 그래프 자료 없음").font(.caption2).foregroundStyle(.secondary) }
        }.padding(.vertical, 4)
    }
}

struct TripEnergyTrendChart: View {
    let points: [TripEnergyPoint]
    var mixedCharging = false
    var hasCharging = false
    private var range: ClosedRange<Double> {
        let values = points.flatMap { [$0.actualSOC] + ($0.predictedSOC.map { [$0] } ?? []) }
        return max(0, (values.min() ?? 0) - 3)...min(100, (values.max() ?? 100) + 3)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(hasCharging ? "예상 + 충전 반영" : "초기 예상").foregroundStyle(.orange)
                Text("실제 잔량").foregroundStyle(.blue)
                Spacer()
                Text("잔량 %").foregroundStyle(.secondary)
            }.font(.caption2)
            Chart {
                ForEach(points.indices, id: \.self) { i in
                    let p = points[i]
                    LineMark(x: .value("경과 분", p.elapsedSeconds / 60), y: .value("실제 잔량", p.actualSOC), series: .value("종류", "실제"))
                        .foregroundStyle(Color.blue).interpolationMethod(.stepEnd)
                    if let predicted = p.predictedSOC, !mixedCharging {
                        LineMark(x: .value("경과 분", p.elapsedSeconds / 60), y: .value("초기 예상", predicted), series: .value("종류", "초기 예상"))
                            .foregroundStyle(Color.orange).lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    }
                }
            }.chartYScale(domain: range).chartYAxis { AxisMarks(position: .leading) }
                .chartXAxisLabel("경과 시간 (분)").frame(height: 150)
                .accessibilityLabel("트립 초기 예상 잔량과 실제 잔량 변화 그래프")
                .accessibilityIdentifier("energy.forecast.chart")
            Text(mixedCharging ? "충전량 미확인 · 예상선 비교 보류" : points.contains(where: { $0.predictedSOC != nil }) ?
                 "초기 예측 전비 + 관측 충전량 · 실제 잔량은 수신 시점 기준" : "주행거리 미수신 · 실제 잔량만 표시")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(.top, 6)
    }
}
