import SwiftUI

struct MonthClosingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var month: Date
    init(month: Date = Date()) { _month = State(initialValue: month) }
    private var interval: DateInterval? { Calendar.current.dateInterval(of: .month, for: month) }
    private func within(_ value: Double?) -> Bool { guard let value, let interval else { return false }; let date = Date(timeIntervalSince1970: value / 1000); return date >= interval.start && date < interval.end }
    private var charges: [Object] { model.output.object("charging").rows("rows").filter { within($0.number("at")) } }
    private var maintenance: [Object] { model.state.rows("maintenance").filter { within($0.number("at")) } }
    private var trips: [Object] { model.state.rows("trips").filter { within($0.number("end")) } }
    private var confirmed: Double { charges.compactMap { $0.number("cost") }.reduce(0, +) }
    private var estimated: Double { charges.filter { $0.number("cost") == nil }.compactMap { $0.number("estimatedCost") }.reduce(0, +) }
    private var unknown: Int { charges.filter { $0.number("cost") == nil && $0.number("estimatedCost") == nil }.count }
    private var serviceCost: Double { maintenance.compactMap { $0.number("cost") }.reduce(0, +) }
    private var report: String {
        "\(month.formatted(.dateTime.year().month())) 결산\n확인 충전비 \(valueText(confirmed))원\n추정 충전비 \(valueText(estimated))원\n충전비 미확인 \(unknown)회\n확인 정비비 \(valueText(serviceCost))원\n확인 지출 합계 \(valueText(confirmed + serviceCost))원\n주행 \(trips.count)회 · 거리 \(valueText(trips.compactMap { $0.number("distanceKm") }.reduce(0,+), digits:1)) km\n확인 지출은 기록된 충전 결제액과 정비비 기준. 추정 충전비는 합계와 분리, 미등록 톨비·보험·기타 비용은 포함하지 않음."
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width:44,height:44) }.accessibilityLabel("이전 달")
                    Spacer(); Text(month, format: .dateTime.year().month()).font(.title2.bold()); Spacer()
                    Button { move(1) } label: { Image(systemName: "chevron.right").frame(width:44,height:44) }.accessibilityLabel("다음 달")
                }
                CompanionSection(title:"충전비",symbol:"bolt.fill") {
                    LabeledContent("확인 결제액",value:valueText(confirmed)+"원")
                    LabeledContent("추정 금액",value:valueText(estimated)+"원")
                    LabeledContent("금액 미확인",value:"\(unknown)회")
                    Text("0원 결제는 확인 결제액에 포함. 미확인 금액을 0원으로 가정하지 않음.").font(.caption).foregroundStyle(.secondary)
                }
                CompanionSection(title:"기록된 지출",symbol:"wonsign.circle") {
                    LabeledContent("확인 정비비",value:valueText(serviceCost)+"원")
                    LabeledContent("확인 지출 합계",value:valueText(confirmed+serviceCost)+"원").font(.headline)
                    Text("확인된 충전 결제액+정비비만 합산함. 주행 소비량 환산 비용을 다시 더하지 않음. 미등록 톨비·보험·기타 지출 제외.").font(.caption).foregroundStyle(.secondary)
                }
                CompanionSection(title:"주행·기록",symbol:"road.lanes") {
                    LabeledContent("주행",value:"\(trips.count)회")
                    LabeledContent("부분 기록",value:"\(trips.filter { $0.flag("missing") }.count)회")
                    Text("충전은 시작일, 주행은 종료일 기준의 달력 월 집계임. 최근 30일과 구분함.").font(.caption).foregroundStyle(.secondary)
                    ShareLink("결산 텍스트 공유",item:report)
                }
            }.padding(16).frame(maxWidth:640).frame(maxWidth:.infinity)
        }.background(Theme.bg).navigationTitle("월간 결산")
    }
    private func move(_ delta:Int) { month = Calendar.current.date(byAdding:.month,value:delta,to:month) ?? month }
}

struct BatteryEvidenceView: View {
    @EnvironmentObject private var model: AppModel
    private var rows: [Object] { model.output.object("charging").rows("rows").sorted { ($0.number("at") ?? 0) > ($1.number("at") ?? 0) } }
    var body: some View {
        List {
            Section {
                Text("차량 보고량·배터리 저장량·공급량·SOC 변화의 출처를 기록별로 확인함. 서로 다른 에너지 종류를 열화율의 같은 기준으로 섞지 않음.").font(.subheadline)
                NavigationLink("용량 비교 기준·배터리 교체일") { BatteryHealthReferenceSettingsView() }
            }
            ForEach(Array(rows.prefix(200).enumerated()),id:\.offset) { _, row in
                Section(dateText(row.number("at"))) {
                    Text(row.string("place").isEmpty ? "장소 미확인" : row.string("place")).font(.headline)
                    Text(row.string("source")).font(.caption).foregroundStyle(.secondary)
                    value("차량 보고 충전량",row.number("vehicleReportedKWh"),"kWh")
                    value("저장량 · 확인 입력",row.number("storedKWh"),"kWh")
                    value("공급량",row.number("supplyKWh") ?? row.number("nasSupplyKWh"),"kWh")
                    value("시작 잔량",row.number("startSOC"),"%")
                    value("종료 잔량",row.number("endSOC"),"%")
                    if !row.string("reviewReason").isEmpty { Text(row.string("reviewReason")).font(.caption).foregroundStyle(.orange) }
                    ChargeCostDetails(charge:row)
                }
            }
            if rows.isEmpty { Text("검토할 충전 기록 없음").foregroundStyle(.secondary) }
        }.navigationTitle("충전량·계산 근거")
    }
    private func value(_ label:String,_ number:Double?,_ unit:String)->some View { LabeledContent(label,value:number.map { valueText($0,digits:2)+" "+unit } ?? "미수신") }
}
