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
    @ObservedObject private var typecast = TypecastClient.shared
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

            // MARK: - Typecast AI High-Quality Voice Section
            Section("타입캐스트 (Typecast) AI 고품질 음성") {
                TypecastSettingsSection()
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

struct TypecastSettingsSection: View {
    @ObservedObject private var typecast = TypecastClient.shared
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Toggle("타입캐스트 AI 음성 사용 (선택)", isOn: $typecast.isEnabled)

        if typecast.isEnabled {
            keyPoolSection
            presetsSection
            complementSection
            bypassSection
            auditionSection

            if !typecast.lastStatus.isEmpty {
                Text(typecast.lastStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            InfoRow("타입캐스트 멀티 계정 안내", "계정을 4~5개 등록해두시면 각 계정의 15,000 크레딧(4개 등록 시 60,000자, 5개 등록 시 75,000자)을 1번부터 차례대로 자동 소진합니다. 한 번 생성된 오디오는 앱에 영구 캐싱되어 0크레딧으로 즉시 재생됩니다.")
        }
    }

    private var keyPoolSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("API Key 계정 풀 (최대 5개 연계)")
                    .font(.caption.weight(.semibold))
                Spacer()
                if typecast.validApiKeys.count > 1 {
                    Button {
                        _ = typecast.switchToNextKey()
                        model.voice.say("\(typecast.activeKeyIndex + 1)번 계정으로 전환했습니다.", category: "voiceControl")
                    } label: {
                        Label("계정 전환 (\(typecast.activeKeyIndex + 1)/\(typecast.validApiKeys.count))", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption2.weight(.bold))
                    }
                    .buttonStyle(.bordered)
                }
            }

            let count = typecast.validApiKeys.count
            let totalCredits = count * 15000
            Text(count == 0 ? "계정별 API Key를 등록하세요. 계정당 매월 15,000 무료 크레딧이 제공됩니다." : "현재 \(count)개 계정 연계됨 (매월 총 \(totalCredits.formatted())자 크레딧 자동 순차 소진 지원)")
                .font(.caption2)
                .foregroundStyle(count > 1 ? .green : .secondary)

            VStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { idx in
                    HStack(spacing: 6) {
                        Text("\(idx + 1)")
                            .font(.caption2.weight(.bold))
                            .frame(width: 14)
                            .foregroundStyle(typecast.activeKeyIndex == idx ? .blue : .secondary)

                        SecureField(idx == 0 ? "1번 메인 API Key (기본)" : "\(idx + 1)번 보조 계정 API Key (선택)", text: Binding(
                            get: { typecast.apiKeys.indices.contains(idx) ? typecast.apiKeys[idx] : "" },
                            set: { newVal in
                                while typecast.apiKeys.count <= idx { typecast.apiKeys.append("") }
                                typecast.apiKeys[idx] = newVal
                            }
                        ))
                        .font(.system(size: 12, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                        if typecast.activeKeyIndex == idx && typecast.validApiKeys.indices.contains(idx) {
                            Text("활성")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2), in: Capsule())
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("음성 캐릭터 프리셋 & Voice ID")
                .font(.caption.weight(.semibold))

            HStack(spacing: 6) {
                ForEach(TypecastClient.presetVoices, id: \.id) { preset in
                    Button {
                        typecast.selectedVoiceId = preset.id
                        model.voice.say("\(preset.name) 음성을 선택했습니다.", category: "voiceControl")
                    } label: {
                        Text(preset.name)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(typecast.selectedVoiceId == preset.id ? Color.blue : Color.white.opacity(0.12), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField("Voice ID 또는 캐릭터명 직접 입력 (예: 은경, 서현, tc_...)", text: $typecast.selectedVoiceId)
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.top, 2)
        }
    }

    private var complementSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("기존 녹음 음성 미수록 문장 보완", isOn: $typecast.complementRecordedVoices)
                .font(.subheadline.weight(.semibold))

            Text("서희·유미·현지·수빈 음성 선택 시, 녹음 파일이 없는 문장(상세 브리핑·제어 알림 등)을 타입캐스트 AI가 각 캐릭터 Voice ID로 읽어줍니다.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if typecast.complementRecordedVoices {
                VStack(spacing: 5) {
                    characterVoiceRow(name: "유미", text: $typecast.voiceIdYumi)
                    characterVoiceRow(name: "현지", text: $typecast.voiceIdHyeonji)
                    characterVoiceRow(name: "수빈", text: $typecast.voiceIdSubin)
                    characterVoiceRow(name: "서희", text: $typecast.voiceIdSeohee)
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    private var bypassSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("100% 타입캐스트 AI 생성 및 캐시 사용", isOn: $typecast.bypassRecordedVoices)
                .font(.subheadline.weight(.semibold))

            Text("조각난 기존 녹음 파일(WAV)을 일체 사용하지 않고, 모든 안내(길안내·안전운전·브리핑·차량제어)를 100% 타입캐스트 고품질 AI로만 합성하여 로컬 캐시에 영구 보관합니다.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var auditionSection: some View {
        HStack {
            Button {
                typecast.testSpeech()
            } label: {
                Label("타입캐스트 미리듣기", systemImage: "speaker.wave.2.fill")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(typecast.isSynthesizing || !typecast.hasKey)

            Spacer()

            if typecast.cacheFileCount > 0 {
                Button("캐시 삭제 (\(typecast.cacheFileCount)개)") {
                    typecast.clearCache()
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
    }

    private func characterVoiceRow(name: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.caption.weight(.bold))
                .frame(width: 32, alignment: .leading)
            TextField("\(name) Voice ID 또는 캐릭터명", text: text)
                .font(.system(size: 12, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button {
                typecast.testSpeech(text: "안녕하세요, \(name) 안내 음성입니다.", voiceId: text.wrappedValue)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.borderless)
            .disabled(typecast.isSynthesizing || !typecast.hasKey)
        }
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
