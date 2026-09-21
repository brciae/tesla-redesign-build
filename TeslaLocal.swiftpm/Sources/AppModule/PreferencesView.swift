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
    @AppStorage("voiceIdentifier") private var identifier = "typecast:은경"
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
    @ObservedObject private var typecast = TypecastClient.shared

    var body: some View {
        Form {
            Section("음성 안내") {
                Toggle("음성 안내", isOn: $enabled)
                VoiceSelectionControls(identifier: $identifier, style: $deliveryStyle)

                // Moderate thumbnail portrait card (38pt, clean and sleek)
                selectedVoiceCard

                VoicePreviewControls(preview: {
                    let name = currentVoiceName
                    model.voice.preview("안녕하세요. \(name) 음성 안내입니다. 안전 운전하세요.")
                }, stop: { model.stopSpeech() })
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
                    }.navigationTitle("음성 세부 설정").navigationBarTitleDisplayMode(.inline)
                }
            }
        }.navigationTitle("표시·음성 설정").navigationBarTitleDisplayMode(.inline)
            .onChange(of: enabled) { _, value in if !value { model.stopSpeech() } }
            .onChange(of: identifier) { _, newId in
                if newId.hasPrefix("typecast:") {
                    let clean = String(newId.dropFirst(9)).trimmingCharacters(in: .whitespacesAndNewlines)
                    typecast.selectedVoiceId = clean
                }
                model.stopSpeech()
            }
            .onChange(of: deliveryStyle) { _, _ in model.stopSpeech() }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in model.navigation.applyAudioPreferences() }
            .onAppear {
                if identifier.isEmpty || identifier.hasPrefix("recorded:") || identifier.hasPrefix("offline:") || (!identifier.hasPrefix("typecast:") && !TypecastClient.presetVoices.contains(where: { $0.id == identifier })) {
                    identifier = "typecast:은경"
                }
                if identifier.hasPrefix("typecast:") {
                    typecast.selectedVoiceId = String(identifier.dropFirst(9)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
    }

    private var selectedVoiceCard: some View {
        let name = currentVoiceName
        let desc = currentVoiceDesc

        return HStack(spacing: 12) {
            TypecastVoiceThumbnail(voice: name, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("타입캐스트 AI")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15), in: Capsule())
                        .foregroundStyle(.blue)
                }

                Text(desc)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var currentVoiceName: String {
        let clean = identifier.replacingOccurrences(of: "typecast:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return TypecastClient.defaultVoiceId }
        if let preset = TypecastClient.presetVoices.first(where: { $0.id == clean || $0.name == clean }) {
            return preset.name
        }
        return clean
    }

    private var currentVoiceDesc: String {
        let name = currentVoiceName
        if let preset = TypecastClient.presetVoices.first(where: { $0.name == name || $0.id == name }) {
            return preset.desc
        }
        return "사용자 지정 Voice ID"
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
        Toggle("타입캐스트 AI 음성 사용", isOn: $typecast.isEnabled)

        if typecast.isEnabled {
            keyPoolSection
            presetsSection
            auditionSection

            if !typecast.lastStatus.isEmpty {
                Text(typecast.lastStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            InfoRow("타입캐스트 멀티 계정 안내", "계정을 추가하여 등록해두시면 각 계정의 15,000 크레딧을 1번부터 차례대로 자동 소진합니다. 한 번 생성된 오디오는 앱에 영구 캐싱되어 0크레딧으로 즉시 재생됩니다.")
        }
    }

    private var keyPoolSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("API Key 계정 풀 (매월 계정당 15,000자 무료)")
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
                ForEach(0..<typecast.apiKeys.count, id: \.self) { idx in
                    HStack(spacing: 6) {
                        Text("\(idx + 1)")
                            .font(.caption2.weight(.bold))
                            .frame(width: 14)
                            .foregroundStyle(typecast.activeKeyIndex == idx ? .blue : .secondary)

                        SecureField(idx == 0 ? "1번 메인 API Key (기본)" : "\(idx + 1)번 보조 계정 API Key (선택)", text: Binding(
                            get: { typecast.apiKeys.indices.contains(idx) ? typecast.apiKeys[idx] : "" },
                            set: { newVal in
                                if typecast.apiKeys.indices.contains(idx) {
                                    typecast.apiKeys[idx] = newVal
                                }
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

                        if typecast.apiKeys.count > 1 {
                            Button {
                                typecast.removeAccount(at: idx)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.red.opacity(0.8))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Button {
                typecast.addAccount()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                    Text("계정 추가 (+15,000 크레딧 슬롯)")
                }
                .font(.caption.weight(.semibold))
            }
            .padding(.top, 4)
        }
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("음성 캐릭터 프리셋 & Voice ID")
                .font(.caption.weight(.semibold))

            HStack(spacing: 6) {
                ForEach(TypecastClient.presetVoices, id: \.id) { preset in
                    let isSelected = typecast.selectedVoiceId == preset.id || typecast.selectedVoiceId == preset.name
                    Button {
                        typecast.selectedVoiceId = preset.id
                        UserDefaults.standard.set("typecast:\(preset.id)", forKey: "voiceIdentifier")
                        model.voice.say("\(preset.name) 음성을 선택했습니다.", category: "voiceControl", manual: true)
                    } label: {
                        HStack(spacing: 5) {
                            TypecastVoiceThumbnail(voice: preset.name, size: 22)
                            Text(preset.name)
                                .font(.caption.weight(.bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(isSelected ? Color.blue : Color.white.opacity(0.12), in: Capsule())
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
                VStack(alignment: .trailing, spacing: 2) {
                    Text("영구 보관 캐시: \(typecast.cacheFileCount)개 (\(String(format: "%.1f", typecast.cacheTotalSizeMB))MB)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("캐시 비우기") {
                        typecast.clearCache()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
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
