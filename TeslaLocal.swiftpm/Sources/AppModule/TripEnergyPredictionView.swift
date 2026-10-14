import SwiftUI

struct TripEnergyPredictionRow: View {
    let estimate: TripEnergyEstimate
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "battery.75percent")
                Text(estimate.insufficient ? "도착 전 배터리 부족 예상" : String(format: "도착 예상 %.0f%% · %.0f–%.0f%%", estimate.arrivalSOC, estimate.lowSOC, estimate.highSOC))
                    .fontWeight(.semibold).accessibilityIdentifier("energy.forecast.arrival")
            }.foregroundStyle(estimate.belowReserve ? Color.orange : Color.primary)
            Text(String(format: "남은 소비 약 %.1f kWh · %@", estimate.remainingKWh, estimate.basis))
                .accessibilityIdentifier("energy.forecast.consumption")
            Text(estimate.capacityAssumed ? "kWh는 가정 용량 환산 · 범위는 참고 추정" : "관측 용량 환산 · 범위는 참고 추정")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.font(.system(size: 12)).lineLimit(1).minimumScaleFactor(0.8)
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
            if rows.isEmpty { Text("길안내 시작 시 예측을 저장하고, 도착 후 실제 잔량과 비교함.").font(.caption).foregroundStyle(.secondary) }
            else {
                ForEach(Array(rows.prefix(5))) { row in TripEnergyRecordView(record: row) }
                if rows.count > 5 { DisclosureGroup("이전 \(rows.count - 5)회 보기") { ForEach(Array(rows.dropFirst(5))) { row in TripEnergyRecordView(record: row) } } }
            }
            Text("기온·바람·고도·정체를 각각 모델링한 값은 아님. 중간 충전·안내 취소·도착 잔량 미수신은 오차 비교에서 제외함.")
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
            if let error = record.errorSOC, let used = record.actualUsedSOC {
                Text(String(format: "잔량 사용 %.1f%%p · 예측 차이 %+.1f%%p", used, error)).font(.caption).foregroundStyle(.secondary)
            } else { Text(record.chargingObserved ? "중간 충전·잔량 증가 포함 · 비교 제외" : record.arrived ? "도착 잔량 미수신 · 비교 제외" : "안내 취소·목적지 변경 · 비교 제외").font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 4)
    }
}
