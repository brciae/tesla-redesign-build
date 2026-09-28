import SwiftUI
import Charts
import CoreFoundation

struct EnergyCalendarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var month = Date()
    @State private var charging = false
    @State private var selected: Date?
    private var days: [EnergyCalendarDay] {
        EnergyCalendarAnalysis.days(month: month, trips: model.output.object("energy").rows("trips"), parking: model.state.rows("parkingPeriods"), charges: model.output.object("charging").rows("rows"), capacityKWh: model.output.object("energy").number("capacityKWh") ?? 75)
    }
    private var offset: Int { guard let first = days.first else { return 0 }; return (Calendar.current.component(.weekday, from: first.date) - Calendar.current.firstWeekday + 7) % 7 }
    // v91: the body was one expression the type-checker gave up on. Each strip
    // is its own small view now, which is also how it reads on screen.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if model.output.object("charging").number("reviewCount") ?? 0 > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("중복 의심 기록 제외").font(.subheadline.bold()).foregroundStyle(.orange)
                        Text("반복 수집이 의심되는 충전은 합계에서 제외했습니다. 충전 전체 기록에서 원본과 판정 이유를 확인하세요.")
                            .font(.footnote).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                monthHeader
                modePickers
                calendarLegend
                chartStrip
                summaryStrip
                calendarGrid
                selectionCard
                InfoNote("달력 집계 기준", "주행·주차는 종료일, 충전은 시작일에 기록합니다. 영수증과 차량 기록을 연결한 충전 회차별 배터리 충전량을 사용합니다. 차량 측정값을 우선하며 SOC 계산값은 추정입니다. 충전기 공급량만 있는 기록은 배터리 충전량으로 합산하지 않습니다. 비어 있는 날은 기록이 없는 날이며 소비 0을 뜻하지 않습니다. 주차 소비 세부 원인은 소비·비용 메뉴에서 확인할 수 있습니다.")
            }.padding(16)
        }.background(Theme.bg).navigationTitle("에너지 달력")
    }

    private var monthHeader: some View {
        HStack {
            Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("이전 달")
            Spacer()
            Text(month.formatted(.dateTime.year().month())).font(.title3.bold())
            Spacer()
            Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled(Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month))
                .accessibilityLabel("다음 달")
        }
    }

    @ViewBuilder private var modePickers: some View {
        Picker("기록 종류", selection: $charging) { Text("사용").tag(false); Text("충전").tag(true) }.pickerStyle(.segmented)

    }

    private var calendarLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                if charging {
                    Label("충전", systemImage: "circle.fill").foregroundStyle(Theme.green)
                } else {
                    Label("주행", systemImage: "circle.fill").foregroundStyle(.orange)
                    Label("주차", systemImage: "circle.fill").foregroundStyle(.purple)
                }
                Spacer()
                Text("단위 kWh").foregroundStyle(Theme.muted)
            }.font(.caption)
            Text(charging ? "+ 충전량 · 약 %는 배터리 용량 대비 환산값" : "달력 −값은 주행·주차 합계 · km는 주행 거리")
                .font(.caption2).foregroundStyle(Theme.muted)
        }.accessibilityIdentifier("energy.calendar.legend")
    }

    // v90: one muted line for the month's peak, then thin bars on a dotted
    // baseline. No plot frame, no gridlines, no y-axis — the day ticks and the
    // summary rows below carry the numbers.
    private var chartStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(peakText).font(.system(size: 12)).foregroundStyle(Theme.muted)
            energyChart
        }
    }

    private var energyChart: some View {
        Chart(days) { day in
            bars(for: day)
        }
        .chartForegroundStyleScale(["주행": Color.orange, "주차": Color.purple])
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(values: [0]) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [1, 3])).foregroundStyle(Color.white.opacity(0.35))
            }
        }
        .chartXAxis {
            AxisMarks(values: tickDates) { value in
                AxisValueLabel { dayTick(value.as(Date.self)) }
            }
        }
        .frame(height: 150)
    }

    @ChartContentBuilder private func bars(for day: EnergyCalendarDay) -> some ChartContent {
        if charging {
            if hasCharge(day) {
                BarMark(x: .value("날짜", day.date, unit: .day), y: .value("충전량", charge(day)), width: .fixed(4))
                    .clipShape(Capsule())
                    .foregroundStyle(Theme.green)
            }
        } else {
            if day.hasDrive {
                BarMark(x: .value("날짜", day.date, unit: .day), y: .value("사용량", day.driving), width: .fixed(4))
                    .clipShape(Capsule())
                    .foregroundStyle(by: .value("구분", "주행"))
            }
            if day.hasParking {
                BarMark(x: .value("날짜", day.date, unit: .day), y: .value("사용량", day.parking), width: .fixed(4))
                    .clipShape(Capsule())
                    .foregroundStyle(by: .value("구분", "주차"))
            }
        }
    }

    @ViewBuilder private func dayTick(_ date: Date?) -> some View {
        if let date {
            Text(String(Calendar.current.component(.day, from: date)))
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder private var summaryStrip: some View {
        let totalCharge = days.reduce(0.0) { $0 + charge($1) }
        let totalMinutes = days.reduce(0.0) { $0 + $1.chargeMinutes }
        let hasTime = days.contains { $0.hasChargeDuration }
        let missingTime = days.contains { $0.hasUnknownChargeDuration }
        let totalUse = days.reduce(0.0) { $0 + $1.driving + $1.parking }
        let totalDistance = days.reduce(0.0) { $0 + $1.distance }
        VStack(spacing: 10) {
            if charging {
                summaryRow("충전량", String(format: "%.2f", totalCharge), "kWh")
                summaryRow(missingTime && hasTime ? "확인된 충전 시간" : "충전 시간", hasTime ? durationText(totalMinutes) : missingTime ? "미확인" : "—", "")
            } else {
                summaryRow("사용량", String(format: "%.1f", totalUse), "kWh")
                summaryRow("주행 거리", String(format: "%.1f", totalDistance), "km")
            }
        }
        .padding(.vertical, 2)
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 8) {
            ForEach(0..<7, id: \.self) { index in weekdayHeader(index) }
            ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 64) }
            ForEach(days) { day in
                Button { selected = day.date } label: { dayCell(day) }.buttonStyle(.plain)
            }
        }
    }

    private func weekdayHeader(_ index: Int) -> some View {
        let weekday = (Calendar.current.firstWeekday - 1 + index) % 7
        let weekend = weekday == 0 || weekday == 6
        return Text(Calendar.current.shortWeekdaySymbols[weekday])
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(weekend ? Color(red: 0.94, green: 0.42, blue: 0.42) : Theme.muted)
    }

    // v90: the delta the reference apps show — signed kWh and, for a charge,
    // what share of the pack it added.
    private func dayCell(_ day: EnergyCalendarDay) -> some View {
        let isSelected = selected == day.date
        return VStack(spacing: 3) {
            Text(String(Calendar.current.component(.day, from: day.date)))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            dayDelta(day)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(isSelected ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private func dayDelta(_ day: EnergyCalendarDay) -> some View {
        if charging {
            if hasCharge(day) {
                Text(String(format: "+%.1f", charge(day)))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.green)
                if let share = packShare(charge(day)) {
                    Text(share).font(.system(size: 9)).foregroundStyle(Theme.green.opacity(0.75))
                }
            }
        } else if day.hasDrive || day.hasParking {
            Text(String(format: "-%.1f", day.driving + day.parking))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.orange)
            if day.distance > 0 {
                Text(String(format: "%.0f km", day.distance)).font(.system(size: 9)).foregroundStyle(Theme.muted)
            }
        }
    }

    @ViewBuilder private var selectionCard: some View {
        if let selected, let day = days.first(where: { $0.date == selected }) {
            InfoCard {
                Text(selected.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                if charging {
                    Text(String(format: "충전 %.2f kWh", charge(day)))
                } else {
                    Text(String(format: "주행 %.1f kWh · 주차 %.1f kWh · %.1f km", day.driving, day.parking, day.distance))
                }
            }
        }
    }

    /// Label left, value right, unit small — the reference layout for a figure
    /// that is read, not compared.
    private func summaryRow(_ label: String, _ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 14)).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
            if !unit.isEmpty { Text(unit).font(.system(size: 12)).foregroundStyle(Theme.muted) }
        }
    }
    private var peakText: String {
        let peak = charging ? days.map { charge($0) }.max() ?? 0 : days.map { $0.driving + $0.parking }.max() ?? 0
        guard peak > 0 else { return charging ? "이번 달 충전 기록 없음" : "이번 달 사용 기록 없음" }
        return String(format: charging ? "이번 달 최대 충전량 : %.1f kWh" : "이번 달 최대 사용량 : %.1f kWh", peak)
    }
    /// Day ticks the reference keeps: the 1st, then every sixth day, then the last.
    private var tickDates: [Date] {
        guard let first = days.first?.date, let last = days.last?.date else { return [] }
        var dates = stride(from: 0, to: days.count, by: 6).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: first) }
        if let final = dates.last, Calendar.current.dateComponents([.day], from: final, to: last).day ?? 0 >= 3 { dates.append(last) }
        return dates
    }
    private func durationText(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return total >= 60 ? "\(total / 60)시간 \(total % 60)분" : "\(total)분"
    }
    private func packShare(_ kWh: Double) -> String? {
        let capacity = model.output.object("energy").number("capacityKWh") ?? 75
        guard capacity > 0, kWh > 0 else { return nil }
        return String(format: "+약 %.0f%%", kWh / capacity * 100)
    }
    private func charge(_ day: EnergyCalendarDay) -> Double { day.chargeTotal }
    private func hasCharge(_ day: EnergyCalendarDay) -> Bool { day.hasCharge }
    private func move(_ delta: Int) { if let next = Calendar.current.date(byAdding: .month, value: delta, to: month) { month = next; selected = nil } }
}
