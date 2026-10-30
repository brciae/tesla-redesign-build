import SwiftUI

struct ChargeTimeOfUseView: View {
    @EnvironmentObject private var model: AppModel
    @State private var rows: [Object] = []
    @State private var editing: String?
    @State private var scope = "home"
    @State private var match = ""
    @State private var kind = "any"
    @State private var months = Set(1...12)
    @State private var days = Set(0...6)
    @State private var from = "00:00"
    @State private var to = "24:00"
    @State private var rate = ""
    @State private var effectiveFrom = Calendar.current.startOfDay(for: Date())
    @State private var hasEnd = false
    @State private var effectiveTo = Date().addingTimeInterval(86400)
    @State private var message = ""
    var body: some View {
        Form {
            Section("장소·사업자·집 요금") {
                Picker("대상", selection: $scope) { Text("집").tag("home"); Text("장소").tag("place"); Text("사업자").tag("operator") }
                if scope != "home" { TextField(scope == "place" ? "충전 기록의 장소 이름" : "사업자 이름", text: $match) }
                Picker("충전 종류", selection: $kind) { Text("전체").tag("any"); Text("완속 AC").tag("ac"); Text("급속 DC").tag("dc"); Text("슈퍼차저").tag("supercharger") }
                TextField("원/kWh · 무료는 0", text: $rate).keyboardType(.decimalPad)
            }
            Section("시간대 · 한국 표준시") {
                HStack { TextField("시작 HH:mm", text: $from); Text("~"); TextField("종료 HH:mm", text: $to) }.keyboardType(.numbersAndPunctuation)
                Text("예: 09:00~23:00. 자정을 넘는 요금은 22:00~24:00과 00:00~07:00 두 구간으로 나누어 등록함.").font(.caption).foregroundStyle(.secondary)
                selection(Array(0...6), values: $days, labels: ["일", "월", "화", "수", "목", "금", "토"])
            }
            Section("적용 월") { selection(Array(1...12), values: $months, labels: (1...12).map { "\($0)월" }) }
            Section("요금 적용 기간") {
                DatePicker("시작", selection: $effectiveFrom, displayedComponents: [.date, .hourAndMinute])
                Toggle("종료일 지정", isOn: $hasEnd)
                if hasEnd { DatePicker("종료 · 해당 시각부터 제외", selection: $effectiveTo, displayedComponents: [.date, .hourAndMinute]) }
                Text("단가가 바뀌면 이전 구간에 종료일을 지정하고 새 기간으로 등록함. 실제 결제액은 요금 변경으로 덮어쓰지 않음.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button(editing == nil ? "시간대 요금 등록" : "선택한 요금 수정") { save() }.accessibilityIdentifier("tariff.schedule.save")
                if editing != nil { Button("새 구간 작성") { editing = nil; message = "" } }
                if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.orange) }
            }
            Section("등록한 구간") {
                if rows.isEmpty { Text("등록한 시간대 요금 없음").foregroundStyle(.secondary) }
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    Button { edit(row) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text((row.string("scope") == "home" ? "집" : row.string("match")) + " · " + valueText(row.number("rate"), digits: 2) + "원/kWh").font(.subheadline.bold())
                            Text(clock(Int(row.number("fromMinute") ?? 0)) + "~" + clock(Int(row.number("toMinute") ?? 1440))).font(.caption)
                            Text(dateText(row.number("effectiveFrom")) + " ~ " + (row.number("effectiveTo").map { dateText($0) } ?? "종료 없음")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button("이 구간 삭제", role: .destructive) { var next = rows; next.remove(at: index); persist(next) }
                }
            }
            Section {
                Caption("시간대 요금 → 장소·사업자 단가 → 확인 결제 이력 → 기본 단가 순으로 예상액 계산. 구간별 전력량이 없고 단가가 달라지면 시간 비례 추정임을 표시함. 요금이 비어 있는 구간이 섞이면 금액을 확정하지 않음.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("시간대·계절 요금").environment(\.timeZone, TimeZone(identifier: "Asia/Seoul")!)
            .onAppear { rows = model.settings.rows("chargeTariffSchedules") }
    }
    private func selection(_ keys: [Int], values: Binding<Set<Int>>, labels: [String]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: keys.count == 7 ? 7 : 4), spacing: 8) {
            ForEach(Array(keys.enumerated()), id: \.element) { index, value in
                Button { var next = values.wrappedValue; if next.contains(value) { next.remove(value) } else { next.insert(value) }; values.wrappedValue = next } label: {
                    Text(labels[index]).font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                        .background(values.wrappedValue.contains(value) ? Color.blue.opacity(0.18) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).accessibilityAddTraits(values.wrappedValue.contains(value) ? [.isSelected] : [])
            }
        }
    }
    private func minute(_ raw: String) -> Int? {
        let parts = raw.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...24).contains(parts[0]), (0...59).contains(parts[1]), parts[0] < 24 || parts[1] == 0 else { return nil }; return parts[0] * 60 + parts[1]
    }
    private func clock(_ value: Int) -> String { String(format: "%02d:%02d", value / 60, value % 60) }
    private func save() {
        guard let a = minute(from), let b = minute(to), a < b, let value = Double(rate), value.isFinite,
              (0...10000).contains(value), !months.isEmpty, !days.isEmpty, !hasEnd || effectiveTo > effectiveFrom else { message = "시각·요일·월·기간·단가 확인 필요함"; return }
        let id = editing ?? UUID().uuidString
        var row: Object = ["id": id, "scope": scope, "match": match.trimmingCharacters(in: .whitespaces), "kind": kind,
            "timezone": "Asia/Seoul", "months": months.sorted(), "days": days.sorted(), "fromMinute": a, "toMinute": b,
            "rate": value, "effectiveFrom": effectiveFrom.timeIntervalSince1970 * 1000]
        if hasEnd { row["effectiveTo"] = effectiveTo.timeIntervalSince1970 * 1000 }
        var next = rows.filter { $0.string("id") != id }; next.append(row)
        if persist(next) { editing = nil; message = "요금 구간 저장됨 · 예상액 재계산 반영" }
    }
    @discardableResult private func persist(_ next: [Object]) -> Bool {
        model.errorMessage = nil; model.mutate("settings", ["chargeTariffSchedules": next])
        if let error = model.errorMessage { message = error; return false }; rows = next; return true
    }
    private func edit(_ row: Object) {
        editing = row.string("id"); scope = row.string("scope", "home"); match = row.string("match"); kind = row.string("kind", "any")
        months = Set((row["months"] as? [Int]) ?? []); days = Set((row["days"] as? [Int]) ?? [])
        from = clock(Int(row.number("fromMinute") ?? 0)); to = clock(Int(row.number("toMinute") ?? 1440)); rate = row.number("rate").map { String($0) } ?? ""
        effectiveFrom = Date(timeIntervalSince1970: (row.number("effectiveFrom") ?? 0) / 1000)
        hasEnd = row.number("effectiveTo") != nil; effectiveTo = Date(timeIntervalSince1970: (row.number("effectiveTo") ?? Date().timeIntervalSince1970 * 1000) / 1000)
    }
}
