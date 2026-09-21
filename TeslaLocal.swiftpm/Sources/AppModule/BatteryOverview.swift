import SwiftUI
import Charts

/// Shared by the production battery page and native UI probe; no inferred BMS diagnosis.
struct BatteryOverview: View {
    let index: Object
    let usage: Object
    @Binding var days: Int
    private let accent = Color(red: 0.30, green: 0.86, blue: 0.65)
    private static let batteryChartDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M/d HH시"
        return f
    }()

    private static let tripRowDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 HH:mm"
        return f
    }()

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
            let rawTrend = usage.rows("trend").sorted { ($0.number("at") ?? 0) < ($1.number("at") ?? 0) }
            var cleanedTrend: [Object] {
                var list: [Object] = []
                var lastAt: Double = -1
                for pt in rawTrend {
                    guard let at = pt.number("at"), let soc = pt.number("soc"), soc >= 0, soc <= 100 else { continue }
                    if at >= lastAt + 60_000 {
                        list.append(pt)
                        lastAt = at
                    } else if !list.isEmpty {
                        list[list.count - 1] = pt
                        lastAt = at
                    }
                }
                return list
            }
            if !cleanedTrend.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("배터리 잔량 추이").font(.headline)
                        Spacer()
                        if let lastSOC = cleanedTrend.last?.number("soc") {
                            Text("\(Int(lastSOC))%")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.cyan)
                        }
                    }
                    .padding(.bottom, 2)

                    Chart {
                        ForEach(cleanedTrend, id: \.batteryRowID) { point in
                            let at = (point.number("at") ?? 0) / 1000
                            let soc = min(100.0, max(0.0, point.number("soc") ?? 0))
                            AreaMark(
                                x: .value("시각", Date(timeIntervalSince1970: at)),
                                y: .value("잔량", soc)
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.cyan.opacity(0.32), Color.blue.opacity(0.04)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("시각", Date(timeIntervalSince1970: at)),
                                y: .value("잔량", soc)
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(Color.cyan)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                                .foregroundStyle(Color.white.opacity(0.12))
                            AxisValueLabel {
                                if let intVal = value.as(Int.self) {
                                    Text("\(intVal)%").font(.caption2).foregroundStyle(Color.white.opacity(0.55))
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                                .foregroundStyle(Color.white.opacity(0.08))
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(Self.batteryChartDateFormatter.string(from: date))
                                        .font(.system(size: 9))
                                        .foregroundStyle(Color.white.opacity(0.55))
                                }
                            }
                        }
                    }
                    .chartPlotStyle { plotArea in
                        plotArea.clipped()
                    }
                    .frame(height: 155)
                    .clipped()
                }
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


    private func tripRow(_ trip: Object) -> some View {
        HStack(spacing: 8) {
            let start = trip.number("at") ?? 0
            Text(Self.tripRowDateFormatter.string(from: Date(timeIntervalSince1970: start / 1000)))
                .lineLimit(1)
                .foregroundStyle(Color.white.opacity(0.85))
            Spacer(minLength: 4)
            Text(number(trip.number("km")) + " km · " + number(trip.number("soc")) + "%p")
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(Color.white.opacity(0.7))
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
