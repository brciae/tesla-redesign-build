import SwiftUI

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

private func rateNumber(_ text: String) throws -> Any {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if clean.isEmpty { return NSNull() }
    guard let value = Double(clean), value.isFinite, (0...10000).contains(value) else { throw LocalError.message("단가는 0~10000원 범위로 입력해 주세요.") }
    return value
}
