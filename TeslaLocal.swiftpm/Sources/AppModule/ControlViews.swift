import SwiftUI

struct ControlPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.vehicleUnits) private var units
    @ObservedObject var link: VehicleLink
    var category = "body"
    @State private var temperature = 22.0
    @State private var limit = 80
    @State private var enrollment = false
    private var blocked: Bool { model.demo || !link.authentic || !link.controlEnabled || link.controlBusy || link.preparingControl || link.confirmation != nil }
    var body: some View {
        InfoCard {
            Text("차량 제어").font(.headline)
            Caption("버튼을 누르면 실제 차량에 1회 요청함 · 재연결 후 자동 실행 없음")
            if link.controlBusy || link.preparingControl { ProgressView("차량 응답 대기") }
            Text(link.controlStatus).font(.footnote).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if link.commandUncertain {
                Caption("이전 명령 결과 미확인 경고가 남아 있음. 다른 명령이 성공해도 이 경고는 해제되지 않음.")
                Button("직전 미확인 명령의 실제 차량 상태를 확인했음") { link.acknowledgeUnknownResult() }
                    .disabled(link.controlBusy || link.confirmation != nil)
            }
            if category == "body" || category == "security" {
                action("lock", "차량 잠금")
                action("unlock", "차량 잠금 해제")
            }
            if category == "body" {
                action("trunkMove", "트렁크 열기·동작")
                action("trunkClose", "트렁크 닫기")
                action("frunkOpen", "프렁크 열기")
                Caption("트렁크 열기·동작은 Tesla 규격상 토글 명령임. 이미 열렸거나 움직이는 중이면 다른 동작이 될 수 있음. 프렁크 닫기는 지원하지 않음.")
            }
            if category == "climate" {
                action("climateOn", "공조 켜기"); action("climateOff", "공조 끄기")
                Stepper("보낼 앞좌석 온도 \(units.format(temperature, suffix: "°C", digits: 1))", value: $temperature, in: 16...28, step: 0.5).disabled(blocked)
                action("temperature", "앞좌석 온도 \(units.format(temperature, suffix: "°C", digits: 1)) 설정", args: ["value": temperature])
                Caption("현재 설정값이 아닌 전송할 값임. 운전석·조수석에 같은 온도를 요청함.")
            }
            if category == "charge" {
                action("chargeStart", "충전 시작"); action("chargeStop", "충전 중지")
                Stepper("보낼 충전 한도 \(limit)%", value: $limit, in: 50...100).disabled(blocked)
                action("chargeLimit", "충전 한도 \(limit)% 설정", args: ["value": limit])
                action("portOpen", "충전 포트 열기"); action("portClose", "충전 포트 닫기")
                Caption("포트 주변·충전 케이블 상태를 직접 확인해야 함. 차량이 안전 조건에 따라 명령을 거절할 수 있음.")
            }
            DisclosureGroup("처음 사용: 별도 제어 키 등록") {
                Caption("기존 조회 키는 그대로 유지함. 별도 Driver 키는 잠금·공조 등 차량 상태 변경 권한을 가짐. 이 앱은 허용된 수동 명령만 제공하지만 키 자체 권한은 조회용보다 넓음. 등록 요청 후 차량의 키카드와 화면에서 직접 승인해야 함.")
                Button("별도 제어 키 등록 요청…") { enrollment = true }
                    .disabled(model.demo || !link.connected || link.controlBusy || link.confirmation != nil)
                Button("차량 승인 후 조회 재개") { link.authenticate() }.disabled(model.demo || !link.connected || link.controlBusy)
                Caption("최초 차량 승인 후에는 키를 재사용하고 인증을 자동 준비함. 기존 조회 키 권한을 자동 변경하지 않음.")
                Button("인증 다시 준비") { link.prepareControlKeys() }.disabled(blocked)
                Toggle("이 차량의 수동 제어 사용", isOn: Binding(get: { link.controlEnabled }, set: { link.enableControls($0) })).disabled(model.demo || link.controlBusy)
            }
        }.confirmationDialog("차량을 조작할 수 있는 별도 Driver 제어 키 등록을 요청할 것인지 확인 필요", isPresented: $enrollment, titleVisibility: .visible) {
            Button("제어 권한을 확인했으며 등록 요청") { link.enrollControlKey() }
            Button("취소", role: .cancel) {}
        }
    }
    private func action(_ action: String, _ title: String, args: Object = [:]) -> some View {
        Button(title) { link.askControl(action, title: title, args: args) }
            .frame(minHeight: 44).disabled(blocked || !link.controlsReady(category: category)).buttonStyle(.bordered)
    }
}
