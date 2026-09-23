import SwiftUI

struct DrivingInsightsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var telemetry = FleetTelemetryStore.shared
    @State private var days = 30
    @AppStorage("cost.electricity") private var electricity = ""
    @AppStorage("cost.gasoline") private var gasoline = ""
    @AppStorage("cost.gasolineEfficiency") private var gasolineEfficiency = ""
    private var energy: Object { model.output.object("energyPeriods").object(String(days)) }
    private var usage: Object { model.output.object("battery").object(String(days)) }
    private var parking: [FleetParkingBucket] {
        FleetParkingAnalysis.buckets(telemetry.records, vin: model.fleet.selectedVin, from: Date().addingTimeInterval(-Double(days) * 86400), to: Date())
    }
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
                    Caption("최근 \(days)일 · 기록 종료일 기준 · 같은 기간의 소비를 비교합니다.")
                }
                InfoCard {
                    Text("에너지가 쓰인 곳").font(.headline)
                    number("기록 거리", energy.number("totalDistanceKm"), "km")
                    number("주행 소비", energy.number("drivingKWh"), "kWh")
                    HStack {
                        number(parking.isEmpty ? "주차 중 자연방전" : "주차 중 소비", energy.number("parkingKWh"), "kWh")
                        InfoNote("주차 중 소비", "상태·시간 기록으로 확인되는 감시 모드·공조·대기는 세분해 표시합니다. 원인을 나눌 근거가 없는 주차 구간은 자연방전으로 묶습니다.")
                    }
                    number("전체 소비", energy.number("totalKWh"), "kWh")
                    if parking.isEmpty {
                        number("주차 중 자연방전", energy.number("parkingKWh"), "kWh")
                    } else {
                        ForEach(parking) { bucket in
                            HStack {
                                Text(bucket.title).font(.subheadline)
                                Spacer()
                                Text(String(format: "%.0f분", bucket.seconds / 60)).monospacedDigit()
                                if bucket.energySeconds >= bucket.seconds * 0.95 {
                                    Text(String(format: "· %.2f kWh", bucket.measuredKWh)).monospacedDigit()
                                }
                            }
                        }
                        InfoNote("주차 소비 세부 분류", "연속해서 확인된 주차 상태와 감시 모드·공조 상태로 구간을 나눕니다. 전력량은 해당 구간 전체 소비입니다. 누적 에너지 계수가 함께 수신된 구간만 kWh를 표시합니다.")
                    }
                    InfoNote("계산 기준", energy.string("note"))
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
                    } else { Caption("자주 이용하는 충전 단가와 비교 차량 연비를 입력하면 같은 거리의 비용 차이를 계산합니다.") }
                }
                InfoCard {
                    Text("분석 가능한 운전 습관").font(.headline)
                    Caption("주행 전비와 종합 전비의 차이가 크면 주차 중 소비부터 살펴보세요. 두 수치가 함께 낮아지는 날에는 짧은 이동, 외기 온도, 공조 사용량을 이전 주행과 비교하는 것이 도움이 됩니다.")
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
