import SwiftUI
import AVFoundation

private struct VehicleUnitsKey: EnvironmentKey { static let defaultValue = VehicleUnits() }
extension EnvironmentValues {
    var vehicleUnits: VehicleUnits { get { self[VehicleUnitsKey.self] } set { self[VehicleUnitsKey.self] = newValue } }
}

struct PreferencesView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("unitDistance") private var distance = "km"
    @AppStorage("unitTemperature") private var temperature = "C"
    @AppStorage("unitPressure") private var pressure = "bar"
    @AppStorage("voiceEnabled") private var enabled = true
    @AppStorage("voiceIdentifier") private var identifier = "recorded:yumi"
    @AppStorage("voiceDeliveryStyle") private var deliveryStyle = "standard"
    @AppStorage("voiceRate") private var rate = 0.47
    @AppStorage("voiceVolume") private var volume = 0.8
    @AppStorage("voiceDuck") private var duck = true
    @AppStorage("voiceQuietEnabled") private var quiet = false
    @AppStorage("voiceQuietStart") private var quietStart = 22
    @AppStorage("voiceQuietEnd") private var quietEnd = 7
    @AppStorage("navVoiceEnabled") private var navVoice = true
    @AppStorage("navSafetyVoice") private var navSafety = true
    @AppStorage("navVoiceDetail") private var navDetail = 0
    @AppStorage("voiceBriefDetail") private var detail = false
    @ObservedObject private var voicePack = OfflineVoicePack.shared
    var body: some View {
        Form {
            // v34: one decision per row. Everything that is not "which voice" moved to 고급.
            Section("음성 안내") {
                Toggle("음성 안내", isOn: $enabled)
                VoiceSelectionControls(identifier: $identifier, style: $deliveryStyle)
                // v42: what the recorded voice does and does not cover, said plainly rather than left
                // for the owner to work out from which sentences suddenly sound different.
                if let recorded = RecordedVoice.resolved(identifier) {
                    // v43: the picker is a menu, so the chosen character is shown once more here,
                    // where there is room for the portrait at a size worth looking at.
                    HStack(spacing: 12) {
                        VoicePortrait(url: recorded.portrait, name: recorded.name, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recorded.name).font(.headline)
                            if !recorded.style.isEmpty {
                                Text(recorded.style).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    InfoRow("녹음 안내 음성", "자주 쓰는 안내 \(recorded.count)문장은 합성하지 않고 미리 녹음된 음원을 그대로 재생함. 회전 안내는 '삼백 미터 앞'과 '좌회전입니다' 두 음원을 이어 붙이고, 말하는 거리는 녹음이 있는 값(50·100·200·300·400·500·700m, 1·2·3km)으로 맞춰 안내함. 녹음에 없는 문장(숫자·지명이 들어간 브리핑 등)은 앱 내장 엔진이 읽음. " + RecordedVoice.credit + " · 개인용.")
                }
                // v37: the 10/20/30대 character voices exist only once the on-device engine is installed,
                // so the download sits right under the picker instead of three screens away.
                if !voicePack.ready {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("캐릭터 음성 (10대·20대·30대)은 앱 내장 음성 엔진이 필요함").font(.subheadline)
                        OfflineVoicePackRow()
                    }
                }
                VoicePreviewControls(preview: { model.voice.preview("안녕하세요. 안내를 시작합니다.") }, stop: { model.stopSpeech() })
                VoiceStatus(voice: model.voice)
            }
            Section("내비 안내") {
                Toggle("길안내 음성", isOn: $navVoice)
                Toggle("안전운행·과속 경고", isOn: $navSafety)
                Picker("안내 빈도", selection: $navDetail) {
                    Text("간단").tag(0); Text("보통").tag(1); Text("자세히").tag(2)
                }.pickerStyle(.segmented).accessibilityIdentifier("nav.voice.detail")
                InfoRow("안내 빈도", "간단: 교차로에 가까워졌을 때의 회전 안내와 실제 위험 구간만 안내함. 보통: 중간 거리 회전 안내와 경로 변경 안내를 추가함. 자세히: 카카오 내비가 제공하는 안내를 모두 읽음(버스전용차로·하이패스·직진 안내 포함).")
            }
            Section("차량 표시 단위") {
                Picker("거리·속도", selection: $distance) { Text("km · km/h").tag("km"); Text("mi · mph").tag("mi") }
                Picker("온도", selection: $temperature) { Text("°C").tag("C"); Text("°F").tag("F") }
                Picker("공기압", selection: $pressure) { Text("bar").tag("bar"); Text("psi").tag("psi"); Text("kPa").tag("kPa") }
                InfoRow("표시 단위", "앱 화면 표시만 바뀜. 차량 내 설정과 지도 앱 단위는 그대로 유지됨.")
            }
            Section("고급") {
                NavigationLink("음성 세부 설정") {
                    Form {
                        Section("음성 조절") {
                            slider("속도", value: $rate, range: 0.3...0.6)
                            slider("안내 음량", value: $volume, range: 0...1)
                            Toggle("안내 중 음악 소리 줄이기", isOn: $duck)
                            VoiceAdvancedControls(identifier: $identifier, style: $deliveryStyle)
                        }
                        Section("자동 안내 항목") {
                            VoiceCategoryToggle(title: "탑승 인사에 배터리 잔량 포함", key: "voiceConnection")
                            VoiceCategoryToggle(title: "차량 제어의 처리 응답", key: "voiceControl")
                            Toggle("잔량 안내에 주행 가능 거리 포함", isOn: $detail)
                            InfoRow("안내 시점", "탑승당 1회만 안내함. 안내 문구 편집은 자동화 탭에서 가능함.")
                        }
                        Section("조용시간") {
                            Toggle("차량 자동 브리핑 쉬기", isOn: $quiet)
                            if quiet {
                                Picker("시작", selection: $quietStart) { ForEach(0..<24, id: \.self) { Text("\($0)시").tag($0) } }
                                Picker("종료", selection: $quietEnd) { ForEach(0..<24, id: \.self) { Text("\($0)시").tag($0) } }
                            }
                            InfoRow("적용 범위", "시작과 종료가 같은 시각이면 제한하지 않음. 직접 누른 읽기와 길안내 음성은 조용시간에도 나옴.")
                        }
                        Section("음성 만들기") {
                            NavigationLink("음성 스튜디오") { VoiceStudioView(identifier: $identifier) }
                            OfflineVoicePackRow()
                        }
                    }.navigationTitle("음성 세부 설정").navigationBarTitleDisplayMode(.inline)
                }
            }
        }.navigationTitle("표시·음성 설정").navigationBarTitleDisplayMode(.inline)
            .onChange(of: enabled) { _, value in if !value { model.stopSpeech() } }
            .onChange(of: identifier) { _, _ in model.stopSpeech() }
            .onChange(of: deliveryStyle) { _, _ in model.stopSpeech() }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in model.navigation.applyAudioPreferences() }
            .onAppear {
                if identifier.isEmpty || (!identifier.hasPrefix(RecordedVoice.prefix) && !identifier.hasPrefix("offline:") && AVSpeechSynthesisVoice(identifier: identifier) == nil) {
                    identifier = RecordedVoice.voices.first?.id ?? "recorded:yumi"
                }
            }
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) { HStack { Text(title); Spacer(); Text(String(format: "%.2f", value.wrappedValue)).monospacedDigit() }; Slider(value: value, in: range) }
    }
}
private struct VoiceCategoryToggle: View {
    let title: String
    @AppStorage private var enabled: Bool
    init(title: String, key: String) { self.title = title; _enabled = AppStorage(wrappedValue: true, key) }
    var body: some View { Toggle(title, isOn: $enabled) }
}
struct VoiceStatus: View {
    @ObservedObject var voice: VoiceCoordinator
    var body: some View {
        if !voice.notice.isEmpty { Text(voice.notice).font(.caption).foregroundStyle(.orange) }
        if !voice.lastText.isEmpty { Text(voice.playbackState + ": " + voice.lastText).font(.caption).foregroundStyle(Theme.muted) }
        if !voice.outputDescription.isEmpty { Text(voice.outputDescription).font(.caption).foregroundStyle(Theme.muted) }
    }
}
