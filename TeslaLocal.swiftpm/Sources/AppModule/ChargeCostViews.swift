import SwiftUI

struct ChargingSummary: View {
    let rows: [Object]
    let days: Int
    private var summary: ChargePeriodSummary { ChargePeriodSummary(rows: rows, days: days) }
    private var selected: [Object] { summary.rows }
    private func total(_ key: String) -> Double? { summary.total(key) }
    private var minutes: Double? {
        let values = selected.compactMap { row -> Double? in
            guard !row.flag("collectedAfterEnd"), row["startTimeObserved"] as? Bool != false,
                  row["endTimeObserved"] as? Bool != false,
                  let start = row.number("at"), let end = row.number("end"), end > start else { return nil }
            return (end - start) / 60000
        }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("최근 \(days)일 충전").font(.headline)
            HStack {
                metric("총 충전량", total("chargedKWh"), digits: 1, unit: "kWh")
                metric("총 충전비", summary.cost, unit: "원")
            }
            HStack {
                metric("충전 횟수", Double(selected.count), unit: "회")
                metric("충전 시간", minutes, unit: "분")
            }
            if selected.contains(where: { $0.flag("chargeEnergyEstimated") || ($0.number("cost") == nil && $0.number("estimatedCost") != nil) }) {
                Caption("추정값 포함 · 상세 기록에서 근거 확인")
            }
            if selected.contains(where: { $0.number("chargedKWh") == nil || $0.number("totalCost") == nil }) {
                Caption("확인 가능한 데이터 기준 · 추가 수신 시 자동 보완")
            }
        }
    }
    private func metric(_ title: String, _ value: Double?, digits: Int = 0, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(valueText(value, digits: digits) + " " + unit).font(.title3.weight(.semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChargeCostDetails: View {
    let charge: Object
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !charge.string("place").isEmpty { Text(charge.string("place")).font(.subheadline) }
            Caption(charge.string("chargeTypeLabel") + (charge.string("chargeOperator").isEmpty ? "" : " · " + charge.string("chargeOperator")))
            if charge.number("cost") == nil {
                if let amount = charge.number("estimatedCost") {
                    Text("예상 충전금액 " + valueText(amount) + "원").font(.headline)
                }
                if let rate = charge.number("estimatedUnitPrice") {
                    Caption("적용 단가 " + valueText(rate, digits: 2) + "원/kWh · " + charge.string("costBasis"))
                }
                Caption(charge.string("costRateSource"))
                if !charge.string("tariffURL").isEmpty {
                    Caption(charge.string("tariffCondition"))
                    if let url = URL(string: charge.string("tariffURL")) { Link("사업자 공식 요금 · " + charge.string("tariffChecked") + " 확인", destination: url).font(.caption) }
                }
                Caption("예상액은 현재 기준으로 계산합니다. 할인·로밍·시간대·혼잡 요금은 실제 결제액과 다를 수 있습니다.")
            }
        }
    }
}

struct ChargeRateSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var slow = ""
    @State private var fast = ""
    @State private var supercharger = ""
    @State private var rules: [Object] = []
    @State private var match = ""
    @State private var scope = "place"
    @State private var kind = "any"
    @State private var rate = ""
    @State private var message = ""
    var body: some View {
        Form {
            LocalBriefingControls(title: "충전 단가") { ["등록한 단가와 과거 결제 내역으로 예상 충전 금액을 계산합니다.", "직접 입력한 결제액이 우선합니다."] }
            Section("기본 예상 단가 · 원/kWh") {
                NavigationLink("사업자 공식 단가·회원가 적용") { PublishedChargeRateSettings() }
                NavigationLink("집 충전 범위·주소 변경") { HomeChargingSettingsView() }
                TextField("집·완속 기준", text: $slow).keyboardType(.decimalPad)
                TextField("급속 기준 · 미등록 시 350", text: $fast).keyboardType(.decimalPad)
                TextField("슈퍼차저 기준 · 미등록 시 급속 기준", text: $supercharger).keyboardType(.decimalPad)
                Text("350원은 사업자 확정 요금이 아닌 조정 가능한 임시 계산값입니다. 집 위치는 내비에 저장한 집 좌표로 대조합니다. 완속 기준을 다른 장소에 적용한 경우 현장 단가 미확인으로 표시합니다.").font(.caption)
                Button("기본 단가 저장") { _ = save(rules) }
            }
            Section("장소·사업자 단가 추가") {
                Picker("적용 대상", selection: $scope) { Text("장소").tag("place"); Text("사업자").tag("operator") }
                TextField(scope == "place" ? "기록의 충전 장소명" : "충전 사업자명", text: $match)
                Picker("충전 방식", selection: $kind) {
                    Text("전체").tag("any"); Text("완속 AC").tag("ac"); Text("급속 DC").tag("dc"); Text("슈퍼차저").tag("supercharger")
                }
                TextField("단가 원/kWh · 무료는 0", text: $rate).keyboardType(.decimalPad)
                Button("단가 추가·갱신") {
                    do {
                        let name = match.trimmingCharacters(in: .whitespacesAndNewlines)
                        let normalized = name.lowercased().filter { !$0.isWhitespace }
                        guard !name.isEmpty, let value = Double(rate), value.isFinite, (0...10000).contains(value) else { throw LocalError.message("이름과 0~10000원 사이 단가를 입력해 주세요.") }
                        var next = rules.filter { !($0.string("scope") == scope && $0.string("kind") == kind && $0.string("match").lowercased().filter { !$0.isWhitespace } == normalized) }
                        next.append(["id": UUID().uuidString, "scope": scope, "match": name, "kind": kind, "rate": value])
                        if save(next) { match = ""; rate = "" }
                    } catch { message = error.localizedDescription }
                }
                Text("기록의 장소·사업자 이름과 일치하면 자동 적용합니다. 장소 단가 → 사업자 단가 → 같은 장소·사업자의 최근 확인 결제 단가 → 기본 단가 순입니다. 직접 입력한 결제액은 바꾸지 않습니다.").font(.caption)
            }
            Section("등록 단가") {
                ForEach(rules, id: \.selfID) { rule in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(rule.string("match"))
                            Caption((rule.string("scope") == "place" ? "장소" : "사업자") + " · " + (["ac": "완속", "dc": "급속", "supercharger": "슈퍼차저"][rule.string("kind")] ?? "전체"))
                        }
                        Spacer()
                        Text(valueText(rule.number("rate"), digits: 2) + "원/kWh")
                        Button { _ = save(rules.filter { $0.selfID != rule.selfID }) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).accessibilityLabel(rule.string("match") + " 단가 삭제")
                    }
                }
            }
            if !message.isEmpty { Section { Text(message).font(.caption) } }
        }
        .navigationTitle("충전 단가 자동 적용")
        .onAppear {
            slow = model.settings.number("tariff").map { String($0) } ?? ""
            fast = model.settings.number("fastTariff").map { String($0) } ?? ""
            supercharger = model.settings.number("superchargerTariff").map { String($0) } ?? ""
            rules = model.settings.rows("chargeRates")
        }
    }
    @discardableResult private func save(_ next: [Object]) -> Bool {
        do {
            model.errorMessage = nil
            model.mutate("settings", ["tariff": try rateNumber(slow), "fastTariff": try rateNumber(fast), "superchargerTariff": try rateNumber(supercharger), "chargeRates": next])
            guard model.errorMessage == nil else { message = model.errorMessage ?? "저장 실패"; return false }
            rules = next; message = "저장했습니다. 기존 기록의 예상 금액도 다시 계산했습니다."; return true
        } catch { message = error.localizedDescription; return false }
    }
}

struct PublishedChargeRateSettings: View {
    @EnvironmentObject private var model: AppModel
    @State private var catalog: [Object] = []
    private var operators: [String] { Array(Set(catalog.map { $0.string("operator") })).sorted() }
    var body: some View {
        Form {
            Section {
                Text("기본은 비회원가. 체크한 사업자만 자체 회원가를 적용함. 로밍 카드·구독·단지 계약 요금은 별도이며, 직접 등록한 단가와 확인 결제액이 우선함.").font(.caption)
                Text("검색으로 확인한 공식 표준 요금의 저장본임. 실시간 요금 조회가 아니며, 충전일에 유효한 근거가 없으면 예상액을 계산하지 않음.").font(.caption)
            }
            ForEach(operators, id: \.self) { name in
                Section(name) {
                    PublishedChargeMemberToggle(operatorName: name)
                    ForEach(catalog.filter { $0.string("operator") == name }, id: \.selfID) { row in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(row.string("kind") == "ac" ? "완속" : "급속").font(.subheadline.bold())
                            Text("비회원 " + tariffText(row.number("nonmember")) + " · 회원 " + tariffText(row.number("member"))).font(.caption)
                            Text(row.string("condition")).font(.caption).foregroundStyle(.secondary)
                            Text((row.string("from").isEmpty ? "시행일 미확인 · 확인일부터 참고" : row.string("from") + " 기준") + " · 확인 " + row.string("checked")).font(.caption2)
                            if let url = URL(string: row.string("url")) { Link("공식 요금 확인", destination: url).font(.caption) }
                        }
                    }
                }
            }
        }.navigationTitle("사업자 공식 충전 단가")
            .onAppear { catalog = (try? model.runtime.call("chargeTariffCatalog")) as? [Object] ?? [] }
    }
    private func tariffText(_ value: Double?) -> String { value.map { valueText($0, digits: 2) + "원/kWh" } ?? "미확인" }
}

struct PublishedChargeMemberToggle: View {
    @EnvironmentObject private var model: AppModel
    let operatorName: String
    var body: some View {
        Toggle("자체 회원가 적용", isOn: Binding(get: {
            ((model.settings["chargeMemberOperators"] as? [String]) ?? []).contains(operatorName)
        }, set: { enabled in
            var names = model.settings["chargeMemberOperators"] as? [String] ?? []
            names.removeAll { $0 == operatorName }; if enabled { names.append(operatorName) }
            model.mutate("settings", ["chargeMemberOperators": names])
        })).accessibilityIdentifier("charging.member." + operatorName)
    }
}

struct PublishedChargeRatePreview: View {
    @EnvironmentObject private var model: AppModel
    let operatorName: String
    let kind: String
    var ratedKW: Double? = nil
    @State private var quote: Object = [:]
    private var key: String {
        let membership = ((model.settings["chargeMemberOperators"] as? [String]) ?? []).joined(separator: "|")
        let rules = model.settings.rows("chargeRates").map { $0.string("scope") + $0.string("match") + $0.string("kind") + String($0.number("rate") ?? -1) }.joined(separator: "|")
        return operatorName + "|" + kind + "|" + String(ratedKW ?? -1) + "|" + membership + "|" + rules
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if quote.string("tariffURL").isEmpty { Text("사업자 공식 단가 미확인").font(.caption) }
            else if let rate = quote.number("estimatedUnitPrice") {
                Text((quote.flag("memberPricingApplied") ? "회원 표준가 " : "비회원 표준가 ") + valueText(rate, digits: 2) + "원/kWh").font(.caption.bold())
            } else { Text(quote.string("costRateSource")).font(.caption) }
            if !quote.string("tariffCondition").isEmpty { Text(quote.string("tariffCondition")).font(.caption2).foregroundStyle(.secondary) }
            NavigationLink("단가·회원가 설정") { PublishedChargeRateSettings() }.font(.caption)
        }.task(id: key) {
            var request: Object = ["at": Date().timeIntervalSince1970 * 1000, "chargeOperator": operatorName, "chargeType": kind]
            if let ratedKW { request["chargerRatedKW"] = ratedKW }
            quote = (try? model.runtime.call("chargeTariffQuote", request)) as? Object ?? [:]
        }
    }
}

private func rateNumber(_ text: String) throws -> Any {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if clean.isEmpty { return NSNull() }
    guard let value = Double(clean), value.isFinite, (0...10000).contains(value) else { throw LocalError.message("단가는 0~10000원 범위로 입력해 주세요.") }
    return value
}
