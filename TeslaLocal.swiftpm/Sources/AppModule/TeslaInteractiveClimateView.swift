import SwiftUI

/// Controls show measured state separately from the requested settings.
struct TeslaInteractiveClimateView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @State private var requestedTemperature = 22.0
    @State private var seat = 0
    @State private var level = 1
    @State private var busy = false
    @State private var result = ""

    private var blocked: Bool {
        model.demo || busy || model.fleet.isSendingCommand || link.controlBusy || link.preparingControl || link.confirmation != nil
    }

    var body: some View {
        let climate = homePresentation(model, link).object("climate")
        ScrollView {
            VStack(spacing: 18) {
                ScreenBriefingControls(scope: .climate)
                InfoCard {
                    Text("마지막 수신 공조 상태").font(.headline)
                    HStack {
                        Text("실내 \(valueText(climate.number("insideC"), digits: 1))°C")
                        Spacer()
                        Text("실외 \(valueText(climate.number("outsideC"), digits: 1))°C")
                    }
                    Text((climate["isOn"] as? Bool).map { $0 ? "공조 켜짐" : "공조 꺼짐" } ?? "공조 작동 상태 미수신")
                    Text("설정 온도 \(valueText(climate.number("targetC"), digits: 1))°C").foregroundStyle(Theme.muted)
                    HStack {
                        Button("공조 켜기") { model.requestVehicleControl("climateOn", title: "공조 켜기") }
                        Spacer()
                        Button("공조 끄기") { model.requestVehicleControl("climateOff", title: "공조 끄기") }
                    }.buttonStyle(.bordered).disabled(blocked)
                }
                InfoCard {
                    Text("요청할 온도").font(.headline)
                    Stepper(value: $requestedTemperature, in: 16...28, step: 0.5) {
                        Text(String(format: "%.1f°C", requestedTemperature)).monospacedDigit()
                    }.disabled(blocked)
                    Button("온도 변경 요청") {
                        model.requestVehicleControl("temperature", title: "온도 설정", args: ["value": requestedTemperature])
                    }.buttonStyle(.borderedProminent).disabled(blocked)
                    Caption("선택값은 전송할 설정임 · 차량의 현재 온도와 구분함")
                }
                Image("TeslaTopInterior").resizable().scaledToFit().frame(maxHeight: 280).accessibilityHidden(true)
                InfoCard {
                    Text("성에 제거 · 스티어링 휠").font(.headline)
                    HStack {
                        Button("성에 제거 켜기") { run("성에 제거 켜기") { try await model.fleet.setPreconditioningMax(on: true) } }
                        Button("끄기") { run("성에 제거 끄기") { try await model.fleet.setPreconditioningMax(on: false) } }
                    }
                    HStack {
                        Button("휠 열선 켜기") { run("휠 열선 켜기") { try await model.fleet.setSteeringWheelHeater(on: true) } }
                        Button("끄기") { run("휠 열선 끄기") { try await model.fleet.setSteeringWheelHeater(on: false) } }
                    }
                }.buttonStyle(.bordered).disabled(blocked)
                InfoCard {
                    Text("시트 열선 · 통풍 요청").font(.headline)
                    Picker("좌석", selection: $seat) {
                        Text("운전석").tag(0); Text("조수석").tag(1)
                        Text("뒷좌석 왼쪽").tag(2); Text("뒷좌석 가운데").tag(4); Text("뒷좌석 오른쪽").tag(5)
                    }
                    Picker("요청 단계", selection: $level) {
                        Text("끔").tag(0); Text("1단계").tag(1); Text("2단계").tag(2); Text("3단계").tag(3)
                    }.pickerStyle(.segmented)
                    HStack {
                        Button("열선 적용") {
                            let selectedSeat = seat, selectedLevel = level
                            run("시트 열선") { try await model.fleet.setSeatHeater(seatPosition: selectedSeat, level: selectedLevel) }
                        }
                        Button("통풍 적용") {
                            let selectedSeat = seat, selectedLevel = level
                            run("시트 통풍") { try await model.fleet.setSeatCooler(seatPosition: selectedSeat, level: selectedLevel) }
                        }.disabled(seat > 1)
                    }.buttonStyle(.bordered)
                    Caption("지원 좌석·기능은 차량 사양에 따라 다름 · 미지원 응답은 오류로 표시함")
                }.disabled(blocked)
                InfoCard {
                    Text("공조 유지 모드 요청").font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                        ForEach(Array(["끄기", "유지", "반려동물", "캠핑"].enumerated()), id: \.offset) { index, title in
                            Button(title) { run("공조 유지 모드") { try await model.fleet.setClimateKeeperMode(mode: index) } }
                        }
                    }.buttonStyle(.bordered).disabled(blocked)
                }
                if !result.isEmpty { Text(result).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading) }
                Text(model.fleet.commandStatus).font(.caption).foregroundStyle(Theme.muted)
                Caption("풍량·송풍 방향·내외기 순환·독립 A/C·뒷좌석 공조의 개별 제어는 현재 앱에서 지원하지 않음. 차량 화면 또는 Tesla 앱에서 설정 필요.")
            }.padding(16)
        }.background(Theme.bg)
        .onAppear { if let target = climate.number("targetC"), target.isFinite, (16...28).contains(target) { requestedTemperature = target } }
    }

    private func run(_ title: String, action: @escaping () async throws -> Bool) {
        guard !blocked else { return }
        guard model.fleet.isAuthenticated else { result = "이 기능은 Fleet 원격 제어 설정이 필요합니다."; return }
        busy = true; result = title + " 전송 중"
        Task { @MainActor in
            defer { busy = false }
            do {
                guard try await action() else { throw FleetCommandPolicy.failure("차량이 요청을 승인하지 않았습니다.") }
                result = title + " 승인 응답 수신"
                model.voice.say(title + " 승인 응답을 받았습니다.", category: "voiceControl", manual: true)
            } catch { result = error.localizedDescription }
        }
    }
}
