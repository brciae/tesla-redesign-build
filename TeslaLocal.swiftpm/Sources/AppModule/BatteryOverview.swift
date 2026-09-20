import SwiftUI
import Charts

/// Shared by the production battery page and native UI probe; no inferred BMS diagnosis.
struct BatteryOverview: View {
    let index: Object
    let usage: Object
    @Binding var days: Int
    private let accent = Color(red: 0.30, green: 0.86, blue: 0.65)
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("기준 대비 추정 열화율").font(.headline)
                        InfoNote("열화율 추정", "차량이 보고한 충전 자료로 계산한 상대 추정값이며 BMS 진단이 아님. 표시되는 전비·소비량도 모두 관측값 기반 추정임.")
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(index.flag("initial") ? "0" : number(index.number("degradationPercent"))).font(.system(size: 56, weight: .light)).monospacedDigit()
                        Text("%").font(.title2).foregroundStyle(.secondary)
                    }
                    Text(index.flag("initial") ? "초기 가정 · 관측 추정 전" : "관측 용량 기반 상대 추정")
                        .font(.caption).foregroundStyle(index.flag("initial") ? .orange : accent)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 7) {
                    Image(systemName: "waveform.path.ecg").font(.system(size: 32)).foregroundStyle(accent)
                    Text("SOH 기준 100%").font(.subheadline.weight(.semibold))
                    Text("현재 지수 " + (index.flag("initial") ? "100" : number(index.number("soh"))) + "%").font(.caption)
                }
            }.accessibilityIdentifier("battery.health")
            Picker("분석 기간", selection: $days) {
                Text("7일").tag(7); Text("30일").tag(30); Text("90일").tag(90)
            }.pickerStyle(.segmented).accessibilityIdentifier("battery.period")
            // v34: four headline numbers; everything else moved behind "자세한 수치" so the page is readable at a glance.
            HStack {
                measure("주행 전비", usage.object("energy").number("drivingKmPerKWh"), "km/kWh")
                measure("종합 전비", usage.object("energy").number("overallKmPerKWh"), "km/kWh")
            }
            HStack(spacing: 18) {
                measure("거리당 잔량 사용", usage.number("socPer100Km"), "%p/100km")
                measure("기록 거리", usage.number("distanceKm"), "km")
            }
            if !usage.rows("trend").isEmpty {
                HStack(spacing: 8) {
                    Text("배터리 잔량 관측").font(.headline)
                    Spacer(minLength: 4)
                    InfoNote("배터리 잔량 관측", "기록별 시작 → 종료 구간만 이어 그림. 통신이 끊긴 공백 구간은 연결하지 않으므로 선이 끊겨 보일 수 있음.")
                }
                Chart(usage.rows("trend"), id: \.batteryRowID) { point in
                    LineMark(x: .value("시각", Date(timeIntervalSince1970: (point.number("at") ?? 0)/1000)),
                              y: .value("SOC", point.number("soc") ?? 0), series: .value("기록", point.string("segment")))
                        .foregroundStyle(by: .value("구간", point.string("kind")))
                        .lineStyle(StrokeStyle(lineWidth: 3)).symbol(.circle)
                }.chartYScale(domain: 0...100).frame(height: 145)
            }
            DisclosureGroup("자세한 수치") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        measure("주차 소비", usage.object("energy").number("parkingKWh"), "kWh")
                        measure("미분류 소비", usage.object("energy").number("unclassifiedKWh"), "kWh")
                    }
                    if let forecast = index.number("forecastDegradation180") {
                        HStack { measure("180일 후 열화", forecast, "%"); measure("현재 관측 오차", index.number("uncertaintyPercent"), "%p") }
                    } else {
                        Text("열화 전망 · 개인 용량 추세 보정 중").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 18) {
                        measure("누적 잔량 사용", usage.number("driveSOC"), "%p")
                        measure("누적 충전 회복", usage.number("chargeSOC"), "%p")
                    }
                    HStack(spacing: 18) {
                        measure("관측 방전 환산", usage.number("observedDischargeCycles"), "회")
                        measure("운행당 SOC 감소 중앙값", usage.number("medianDischargeDepth"), "%p")
                    }
                    HStack {
                        pattern("battery.100percent", "90% 이상 충전", usage.number("highEndCharges"))
                        pattern("battery.25percent", "20% 미만 도착", usage.number("lowEndTrips"))
                        pattern("arrow.down.circle", "50%p 이상 사용", usage.number("deepDischargeTrips"))
                    }
                    HStack {
                        measure("관측 전력 사용", usage.number("observedUsedKWh"), "kWh")
                        measure("관측 회생", usage.number("observedRecoveredKWh"), "kWh")
                    }
                    HStack(spacing: 8) {
                        Text("전력 관측 \(number(usage.number("powerCoverage")))%").font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        InfoNote("계산 근거·한계", basisNote)
                    }
                }.padding(.top, 10)
            }
            let tripRows = usage.rows("tripRows")
            if !tripRows.isEmpty {
                Text("운행별 배터리 사용").font(.headline)
                ForEach(Array(tripRows.suffix(3).reversed()), id: \.batteryRowID) { trip in tripRow(trip) }
                if tripRows.count > 3 {
                    DisclosureGroup("전체 \(tripRows.count)회 보기") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(tripRows.reversed()), id: \.batteryRowID) { trip in tripRow(trip) }
                        }.padding(.top, 8)
                    }
                }
            }
        }.padding(18).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
            .accessibilityIdentifier("battery.overview")
    }
    private var basisNote: String {
        var lines: [String] = []
        if !index.string("note").isEmpty { lines.append(index.string("note")) }
        lines.append("비교 가능한 충전 자료 \(number(index.number("sampleCount")))회 · 초기 용량 \(number(index.number("baselineCapacityKWh"))) kWh → 최근 \(number(index.number("recentCapacityKWh"))) kWh")
        lines.append("방전 환산 = 관측된 운행 전후 SOC 감소 합계 ÷ 100. 중간 통신 공백 기록도 포함하므로 전체 배터리 사이클과 다름. 누적 충전 회복은 기간 합계라 100%p를 넘을 수 있음.")
        lines.append("완전 운행 기록 \(count(usage.number("completeTrips")))/\(count(usage.number("tripCount")))회 · 부분 충전 \(count(usage.number("partialChargeCount")))회")
        lines.append("전력 사용·회생은 관측한 모터 전력의 적산이라 전체 배터리 소비·전비와 다를 수 있음. 주차 감소 \(number(usage.number("unexplainedParkingSOC")))%p · 혼합 \(count(usage.number("mixedParkingCount")))구간 제외.")
        if !usage.string("note").isEmpty { lines.append(usage.string("note")) }
        if !index.string("forecastNote").isEmpty { lines.append(index.string("forecastNote")) }
        return lines.joined(separator: "\n\n")
    }

    private func tripRow(_ trip: Object) -> some View {
        HStack {
            Text(Date(timeIntervalSince1970: (trip.number("at") ?? 0)/1000), style: .date)
            Spacer()
            Text(number(trip.number("km")) + " km · " + number(trip.number("soc")) + "%p")
            if trip.flag("partial") { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange).accessibilityLabel("부분 기록") }
        }.font(.caption).monospacedDigit()
    }

    private func number(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "—" }
    private func count(_ value: Double?) -> String { value.map { String(format: "%.0f", $0) } ?? "—" }
    private func pattern(_ icon: String, _ title: String, _ value: Double?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title2).foregroundStyle(accent)
            Text(count(value) + "회").font(.headline)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
    private func measure(_ title: String, _ value: Double?, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            (Text(number(value)).font(.system(size: 25, weight: .medium)) + Text(" " + unit).font(.system(size: 12)))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension Dictionary where Key == String, Value == Any {
    var batteryRowID: String { string("id") }
}
