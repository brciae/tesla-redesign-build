import SwiftUI
import Charts
import CoreFoundation

struct EnergyCalendarDay: Identifiable {
    let date: Date
    var id: Date { date }
    var driving: Double = 0
    var parking: Double = 0
    var distance: Double = 0
    var chargeSupply: Double = 0
    var chargeVehicle: Double = 0
    var chargeMinutes: Double = 0
    var hasDrive = false
    var hasParking = false
    var hasSupply = false
    var hasVehicleCharge = false
}

enum EnergyCalendarAnalysis {
    static func days(month: Date, trips: [[String: Any]], parking: [[String: Any]], charges: [[String: Any]], capacityKWh: Double, calendar: Calendar = .current) -> [EnergyCalendarDay] {
        guard let interval = calendar.dateInterval(of: .month, for: month), let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        var result = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }.map { EnergyCalendarDay(date: $0) }
        func number(_ row: [String: Any], _ key: String) -> Double? {
            guard let value = row[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
            return value.doubleValue
        }
        func index(_ ms: Double?) -> Int? {
            guard let ms else { return nil }; let date = Date(timeIntervalSince1970: ms / 1000)
            guard interval.contains(date) else { return nil }
            return calendar.component(.day, from: date) - 1
        }
        for trip in trips where trip["duplicate"] as? Bool != true {
            guard let i = index(number(trip, "end")), let energy = number(trip, "estimatedKWh"), energy >= 0 else { continue }
            result[i].hasDrive = true; result[i].driving += energy; result[i].distance += max(0, number(trip, "distanceKm") ?? 0)
        }
        var coveredUntil: Double = -1
        for p in parking.sorted(by: { (number($0, "start") ?? 0) < (number($1, "start") ?? 0) }) where p["classification"] as? String == "parking" {
            guard let start = number(p, "start"), let end = number(p, "end"), start >= coveredUntil, end >= start,
                  let i = index(end), let soc = number(p, "deltaSOC"), (0...100).contains(soc), capacityKWh > 0 else { continue }
            let overlapsCharge = charges.contains { charge in
                guard let at = number(charge, "at") else { return false }
                let finish = number(charge, "end") ?? at + 1
                return start < finish && at < end
            }
            if overlapsCharge { continue }
            coveredUntil = end; result[i].hasParking = true; result[i].parking += soc / 100 * capacityKWh
        }
        for charge in charges {
            guard let i = index(number(charge, "at")) else { continue }
            if let value = number(charge, "supplyKWh"), value >= 0 { result[i].chargeSupply += value; result[i].hasSupply = true }
            if let value = number(charge, "vehicleReportedKWh"), value >= 0 { result[i].chargeVehicle += value; result[i].hasVehicleCharge = true }
            if let start = number(charge, "at"), let end = number(charge, "end"), end >= start { result[i].chargeMinutes += (end - start) / 60000 }
        }
        return result
    }
}

struct EnergyCalendarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var month = Date()
    @State private var charging = false
    @State private var vehicleEnergy = true
    @State private var selected: Date?
    private var days: [EnergyCalendarDay] {
        EnergyCalendarAnalysis.days(month: month, trips: model.output.object("energy").rows("trips"), parking: model.state.rows("parkingPeriods"), charges: model.state.rows("charges"), capacityKWh: model.output.object("energy").number("capacityKWh") ?? 75)
    }
    private var offset: Int { guard let first = days.first else { return 0 }; return (Calendar.current.component(.weekday, from: first.date) - Calendar.current.firstWeekday + 7) % 7 }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("이전 달")
                    Spacer(); Text(month.formatted(.dateTime.year().month())).font(.title3.bold()); Spacer()
                    Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month)).accessibilityLabel("다음 달")
                }
                Picker("기록 종류", selection: $charging) { Text("사용").tag(false); Text("충전").tag(true) }.pickerStyle(.segmented)
                if charging {
                    Picker("에너지 기준", selection: $vehicleEnergy) { Text("차량 충전량").tag(true); Text("결제 공급량").tag(false) }.pickerStyle(.segmented)
                }
                Chart(days) { day in
                    if charging {
                        if hasCharge(day) { BarMark(x: .value("날짜", day.date, unit: .day), y: .value("충전량", charge(day))).foregroundStyle(.mint) }
                    } else {
                        if day.hasDrive { BarMark(x: .value("날짜", day.date, unit: .day), y: .value("사용량", day.driving)).foregroundStyle(by: .value("구분", "주행")) }
                        if day.hasParking { BarMark(x: .value("날짜", day.date, unit: .day), y: .value("사용량", day.parking)).foregroundStyle(by: .value("구분", "주차")) }
                    }
                }.chartForegroundStyleScale(["주행": Color.orange, "주차": Color.purple]).frame(height: 170)
                if charging {
                    Text(String(format: "기록 충전량 %.2f kWh · 기록 시간 %.0f분", days.reduce(0) { $0 + charge($1) }, days.reduce(0) { $0 + $1.chargeMinutes })).font(.headline)
                } else {
                    Text(String(format: "사용 %.1f kWh · 주행 %.1f km", days.reduce(0) { $0 + $1.driving + $1.parking }, days.reduce(0) { $0 + $1.distance })).font(.headline)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 8) {
                    ForEach(0..<7, id: \.self) { index in Text(Calendar.current.shortWeekdaySymbols[(Calendar.current.firstWeekday - 1 + index) % 7]).font(.caption).foregroundStyle(Theme.muted) }
                    ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 64) }
                    ForEach(days) { day in
                        Button { selected = day.date } label: {
                            VStack(spacing: 5) {
                                Text(String(Calendar.current.component(.day, from: day.date))).font(.subheadline.bold())
                                if charging, hasCharge(day) { Text(String(format: "+%.1f", charge(day))).font(.system(size: 10)).foregroundStyle(.mint) }
                                if !charging, day.hasDrive || day.hasParking { Text(String(format: "%.1f", day.driving + day.parking)).font(.system(size: 10)).foregroundStyle(.orange) }
                            }.frame(maxWidth: .infinity).frame(height: 64).background(selected == day.date ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                }
                if let selected, let day = days.first(where: { $0.date == selected }) {
                    InfoCard {
                        Text(selected.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                        if charging { Text(String(format: "충전 %.2f kWh", charge(day))) }
                        else { Text(String(format: "주행 %.1f kWh · 주차 %.1f kWh · %.1f km", day.driving, day.parking, day.distance)) }
                    }
                }
                InfoNote("달력 집계 기준", "주행·주차는 종료일, 충전은 시작일에 기록합니다. 충전량은 차량 보고량과 결제 공급량을 합산하지 않습니다. 비어 있는 날은 기록이 없는 날이며 소비 0을 뜻하지 않습니다. 주차 소비 세부 원인은 소비·비용 메뉴에서 확인할 수 있습니다.")
            }.padding(16)
        }.background(Theme.bg).navigationTitle("에너지 달력")
    }
    private func charge(_ day: EnergyCalendarDay) -> Double { vehicleEnergy ? day.chargeVehicle : day.chargeSupply }
    private func hasCharge(_ day: EnergyCalendarDay) -> Bool { vehicleEnergy ? day.hasVehicleCharge : day.hasSupply }
    private func move(_ delta: Int) { if let next = Calendar.current.date(byAdding: .month, value: delta, to: month) { month = next; selected = nil } }
}
