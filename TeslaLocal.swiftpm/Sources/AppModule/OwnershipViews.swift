import SwiftUI

struct DrivingInsightsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var days = 30
    @State private var electricity = ""
    @State private var gasoline = ""
    @State private var gasolineEfficiency = ""
    private var energy: Object { model.output.object("energyPeriods").object(String(days)) }
    private var usage: Object { model.output.object("battery").object(String(days)) }
    private var comparison: OwnershipAnalysis.CostComparison? {
        OwnershipAnalysis.cost(distanceKm: energy.number("totalDistanceKm"), energyKWh: energy.number("totalKWh"), electricity: Double(electricity), gasoline: Double(gasoline), gasolineEfficiency: Double(gasolineEfficiency))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LocalBriefingControls(title: "주행·소비 분석", summary: { [model.screenBriefing(.battery, days: days)] })
                Picker("분석 기간", selection: $days) { Text("7일").tag(7); Text("30일").tag(30); Text("90일").tag(90) }.pickerStyle(.segmented)
                InfoCard {
                    Text("나의 주행과 전체 소비").font(.headline)
                    HStack {
                        number("주행 전비", energy.number("drivingKmPerKWh"), "km/kWh")
                        Spacer()
                        number("종합 전비", energy.number("overallKmPerKWh"), "km/kWh")
                    }
                    Text(model.screenBriefing(.battery, days: days)).font(.subheadline).lineSpacing(5)
                    Caption("최근 \(days)일 · 기록 종료일 기준. 같은 기간의 주행·주차·미분류 소비를 비교합니다. 차종·계절 평균이나 운전 점수는 검증된 비교 데이터 없이 만들지 않습니다.")
                }
                InfoCard {
                    Text("에너지가 쓰인 곳").font(.headline)
                    number("기록 거리", energy.number("totalDistanceKm"), "km")
                    number("주행 소비", energy.number("drivingKWh"), "kWh")
                    number("주차 소비", energy.number("parkingKWh"), "kWh")
                    number("미분류 소비", energy.number("unclassifiedKWh"), "kWh")
                    Caption(energy.string("note"))
                }
                InfoCard {
                    Text("같은 거리를 달렸을 때의 비용").font(.headline)
                    input("충전 단가 · 원/kWh", text: $electricity)
                    input("휘발유 가격 · 원/L", text: $gasoline)
                    input("비교 차량 연비 · km/L", text: $gasolineEfficiency)
                    if let comparison {
                        number("전기 사용 비용 추정", comparison.electric, "원", digits: 0)
                        number("가솔린 비교 비용", comparison.gasoline, "원", digits: 0)
                        Text(String(format: "동일 거리 에너지 비용 차이 %.0f원", comparison.savings)).font(.headline).foregroundStyle(.mint)
                        Caption("양수는 전기 비용이 적다는 뜻입니다. 실제 결제액·전체 유지비가 아니며 충전 손실, 보험, 세금, 정비비는 포함하지 않습니다.")
                    } else { Caption("세 비교 조건과 주행 기록이 있어야 계산합니다. 예시 화면의 가격·절감액을 내 차량 수치로 사용하지 않습니다.") }
                }
                InfoCard {
                    Text("분석 가능한 운전 습관").font(.headline)
                    Caption("현재 누적 기록으로 전비와 비주행 소비를 분석합니다. 급가속·급제동 빈도, 속도대별 전비, 외기·공조 영향은 시간에 맞춘 Telemetry 표본이 쌓인 뒤 비교할 수 있습니다. 소비량만으로 운전 습관이 나쁘다고 판정하지 않습니다.")
                }
            }.padding(16)
        }.background(Theme.bg).navigationTitle("주행·소비 분석")
        .onAppear { if electricity.isEmpty, let tariff = model.settings.number("tariff") { electricity = String(format: "%.0f", tariff) } }
    }
    private func input(_ label: String, text: Binding<String>) -> some View {
        HStack { Text(label).font(.subheadline); TextField("직접 입력", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 110) }
    }
    private func number(_ label: String, _ value: Double?, _ unit: String, digits: Int = 1) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(label).font(.caption).foregroundStyle(Theme.muted); Text(value.map { String(format: "%.*f %@", digits, $0, unit) } ?? "자료 없음").font(.title3.bold()).monospacedDigit() }
    }
}

struct WarrantyGuideView: View {
    let vin: String
    let odometerKm: Double?
    @State private var start = Date()
    @State private var confirmed = false
    private var key: String { "warranty.start." + vin }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                InfoCard {
                    Text("Model Y L 보증 안내").font(.headline)
                    Caption("대한민국 신차 보증 안내 기준입니다. 내 차량의 계약·보증서는 Tesla 앱의 ‘제원 및 보증 → 보증’에서 확인하세요.")
                    DatePicker("보증서의 보증 시작일", selection: $start, in: ...Date(), displayedComponents: .date)
                    Toggle("보증서에서 시작일을 확인했습니다", isOn: $confirmed).disabled(vin.isEmpty)
                    Caption("확인한 시작일은 이 차량에만 저장합니다. 날짜를 추측해 만료일을 표시하지 않습니다.")
                }
                coverage("기본 차량", years: 4, km: 80000)
                coverage("탑승자 보호장치", years: 5, km: 100000)
                coverage("배터리·구동장치", years: 8, km: 192000)
                coverage("차체 부식", years: 12, km: nil)
                Caption("기간과 거리 중 먼저 도달하는 기준을 적용합니다. 배터리는 해당 보증 기간의 용량 70% 유지 조건이 있으며, 앱의 상대 용량 추정값으로 보증 적용 여부를 판정하지 않습니다. 부식 보증은 약관상 부식 천공에 해당합니다.")
                Link("Tesla 대한민국 보증 원문", destination: URL(string: "https://www.tesla.com/ko_kr/support/vehicle-warranty")!)
            }.padding(16)
        }.background(Theme.bg).navigationTitle("보증 기간")
        .onAppear { if let saved = UserDefaults.standard.object(forKey: key) as? Date { start = saved; confirmed = true } }
        .onChange(of: confirmed) { _, _ in save() }
        .onChange(of: start) { _, _ in save() }
    }
    private func save() {
        guard !vin.isEmpty else { return }
        if confirmed { UserDefaults.standard.set(start, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    }
    private func coverage(_ title: String, years: Int, km: Double?) -> some View {
        InfoCard {
            Text(title).font(.headline)
            Text("\(years)년" + (km.map { String(format: " 또는 %.0f km", $0) } ?? " · 거리 제한 없음"))
            if confirmed, let end = OwnershipAnalysis.warrantyEnd(start: start, years: years) { Text("기간 기준 만료일 " + end.formatted(date: .numeric, time: .omitted)).font(.subheadline) }
            Caption(OwnershipAnalysis.warrantySummary(start: confirmed ? start : nil, years: years, limitKm: km, odometerKm: odometerKm))
        }
    }
}
