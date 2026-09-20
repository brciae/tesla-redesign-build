import SwiftUI

/// v30 voice studio: gender → base speaker → blend → tone → 10-band EQ → effects, audition, save to "내가 만든 음성".
struct VoiceStudioView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var identifier: String
    @ObservedObject private var pack = OfflineVoicePack.shared
    @State private var draft: VoiceProfile = VoiceStudioView.initialDraft()
    @State private var customs: [VoiceProfile] = VoiceLibrary.customs
    @State private var pendingDelete: String?
    @State private var sample = "안녕하세요. 300미터 앞에서 오른쪽 방향입니다. 목적지까지 12분 남았습니다."

    private static func initialDraft() -> VoiceProfile {
        var p = VoiceLibrary.base("F2")
        p.id = "custom:" + UUID().uuidString; p.name = "나만의 음성"
        return p
    }

    var body: some View {
        Form {
            // v37: the studio needs the on-device engine, so the download lives here instead of sending
            // the user back to another screen to find it.
            if !pack.ready {
                Section {
                    Text("앱 내장 음성 엔진이 있어야 들어보기·저장이 동작함.").foregroundStyle(.orange)
                    OfflineVoicePackRow()
                } header: { Text("음성 엔진") }
            }
            if !model.voice.notice.isEmpty {
                Section { Text(model.voice.notice).foregroundStyle(.orange).font(.subheadline) }
            }
            Section("성별과 기본 목소리") {
                Picker("성별", selection: Binding(get: { draft.female }, set: { setGender($0) })) {
                    Text("여성").tag(true); Text("남성").tag(false)
                }.pickerStyle(.segmented)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(bases, id: \.self) { b in baseCard(b) }
                    }.padding(.vertical, 4)
                }
                Menu("프리셋에서 시작") {
                    ForEach(VoiceLibrary.presets.filter { $0.female == draft.female }) { p in
                        Button(p.name) { var copy = p; copy.id = draft.id; copy.name = "나만의 " + p.name; draft = copy.validated() }
                    }
                }
                TextField("이름", text: $draft.name)
            }
            Section {
                Picker("섞을 목소리", selection: $draft.partner) {
                    ForEach(bases, id: \.self) { b in Text(label(b)).tag(b) }
                }
                slider("음색 섞기", value: blendBinding, range: 0...1) { "\(Int(($0 * 100).rounded()))%" }
                slider("말투 섞기", value: rhythmBinding, range: 0...1) { "\(Int(($0 * 100).rounded()))%" }
            } header: { Text("음색 섞기") } footer: { Text("0%는 기본 목소리 그대로, 100%는 섞을 목소리 쪽으로 이동.") }
            Section("어조") {
                slider("음높이", value: $draft.pitch, range: -800...800) { String(format: "%+.1f 반음", $0 / 100) }
                slider("말하기 속도", value: $draft.speed, range: 0.75...1.3) { String(format: "%.2f×", $0) }
                slider("문장 사이 쉼", value: pauseBinding, range: 0...0.6) { String(format: "%.2f초", $0) }
            }
            Section {
                EqualizerView(gains: $draft.eq)
                    .frame(height: 190)
                    .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 8, trailing: 8))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(VoiceLibrary.eqPresets, id: \.name) { preset in
                            Button(preset.name) { withAnimation(.easeOut(duration: 0.2)) { draft.eq = preset.gains } }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
            } header: { Text("10밴드 이퀄라이저") } footer: { Text("막대를 위아래로 끌어 ±12 dB 조절. 합성 후 기기 안에서 처리함.") }
            Section {
                slider("캐릭터 (애니 음색)", value: Binding(get: { (draft.formantShift ?? 1) }, set: { draft.formantShift = $0 <= 1.005 ? nil : $0 }),
                       range: 1...1.4) { $0 <= 1.005 ? "없음" : "\(Int((($0 - 1) / 0.4 * 100).rounded()))%" }
                slider("숨소리", value: Binding(get: { (draft.breathiness ?? 0) }, set: { draft.breathiness = $0 <= 0.005 ? nil : $0 }),
                       range: 0...0.4) { $0 <= 0.005 ? "없음" : "\(Int(($0 / 0.4 * 100).rounded()))%" }
                slider("숨소리 굵기", value: Binding(get: { (draft.breathBody ?? 0) }, set: { draft.breathBody = $0 <= 0.01 ? nil : $0 }),
                       range: 0...1) { $0 <= 0.01 ? "가벼움" : "\(Int(($0 * 100).rounded()))%" }
                slider("생동감 (억양 강조)", value: Binding(get: { (draft.liveliness ?? 0) }, set: { draft.liveliness = $0 <= 0.01 ? nil : $0 }),
                       range: 0...1) { $0 <= 0.01 ? "없음" : "\(Int(($0 * 100).rounded()))%" }
                slider("떨림", value: Binding(get: { (draft.vibrato ?? 0) }, set: { draft.vibrato = $0 <= 0.5 ? nil : $0 }),
                       range: 0...60) { $0 <= 0.5 ? "없음" : "\(Int($0.rounded()))센트" }
                slider("두께 (농후함)", value: Binding(get: { (draft.thickness ?? 0) }, set: { draft.thickness = $0 <= 0.005 ? nil : $0 }),
                       range: 0...0.5) { $0 <= 0.005 ? "없음" : "\(Int(($0 / 0.5 * 100).rounded()))%" }
                slider("온기 (배음)", value: Binding(get: { (draft.warmth ?? 0) }, set: { draft.warmth = $0 <= 0.005 ? nil : $0 }),
                       range: 0...0.6) { $0 <= 0.005 ? "없음" : "\(Int(($0 / 0.6 * 100).rounded()))%" }
            } header: {
                HStack { Text("캐릭터"); Spacer(); InfoNote("캐릭터 음색", "캐릭터: 성도(목의 공명)를 짧게 바꿔 어린 여성 음색을 만듦 — 피치만 올리는 방식과 달리 헬륨 소리가 나지 않음. 숨소리·굵기: 기식음의 양과 대역(가벼운 바람 소리 ↔ 가까운 숨결). 생동감: 합성 음성의 평평한 억양을 실제 억양 방향으로 과장해 기계음 느낌을 줄임. 떨림: 모음이 완벽히 일정하지 않게 흔듦. 두께: 살짝 디튠된 겹목소리로 농후하게. 온기: 부드러운 포화로 배음을 더함.") }
            }
            Section("효과") {
                slider("울림 (공간감)", value: $draft.reverb, range: 0...60) { "\(Int($0))%" }
                slider("무전기 질감", value: $draft.radio, range: 0...70) { "\(Int($0))%" }
                slider("펀치 (또렷한 압축)", value: $draft.punch, range: 0...1) { "\(Int(($0 * 100).rounded()))%" }
            }
            Section {
                TextField("들어볼 문장", text: $sample, axis: .vertical).lineLimit(1...3)
                HStack {
                    Button { model.voice.audition(draft, text: sample) } label: {
                        Label("들어보기", systemImage: "play.fill").frame(minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!pack.ready)
                    Spacer()
                    Button { model.stopSpeech() } label: { Label("중지", systemImage: "stop.fill").frame(minHeight: 44) }
                        .buttonStyle(.borderless)
                }
                if !pack.ready { Text("음성 엔진을 받은 뒤에 들어볼 수 있음.").font(.caption).foregroundStyle(Theme.muted) }
                else if !model.voice.playbackState.isEmpty { Text(model.voice.playbackState).font(.caption).foregroundStyle(Theme.muted) }
                Button {
                    let saved = draft.validated()
                    VoiceLibrary.save(saved); customs = VoiceLibrary.customs
                    identifier = "offline:" + saved.id
                    UserDefaults.standard.set(saved.female ? "female" : "male", forKey: "voiceGender")
                } label: { Label("저장하고 안내 음성으로 사용", systemImage: "checkmark.circle.fill") }
                .disabled(!pack.ready)
            } header: { Text("미리 듣기·저장") }
            if !customs.isEmpty {
                Section("내가 만든 음성") {
                    ForEach(customs) { p in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(p.name)
                                Text((p.female ? "여성 · " : "남성 · ") + label(p.base)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if identifier == "offline:" + p.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { draft = p }
                        // v37: visible controls. A swipe action is invisible until discovered, and the
                        // user could not find a way to remove a voice they had made.
                        .overlay(alignment: .trailing) {
                            Menu {
                                Button { draft = p } label: { Label("편집하기", systemImage: "slider.horizontal.3") }
                                Button { identifier = "offline:" + p.id } label: { Label("안내 음성으로 사용", systemImage: "checkmark.circle") }
                                Button(role: .destructive) { pendingDelete = p.id } label: { Label("삭제", systemImage: "trash") }
                            } label: {
                                Image(systemName: "ellipsis.circle").font(.system(size: 17)).frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).foregroundStyle(Theme.muted).accessibilityLabel(p.name + " 편집·삭제")
                        }
                    }
                }
            }
            Section {
                Button("새 음성 만들기") { draft = Self.initialDraft() }
            }
        }
        .navigationTitle("음성 스튜디오").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("내가 만든 음성 삭제", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                if let id = pendingDelete {
                    VoiceLibrary.delete(id); customs = VoiceLibrary.customs
                    if identifier == "offline:" + id { identifier = "" }
                }
                pendingDelete = nil
            }
        } message: { Text("되돌릴 수 없음. 안내 음성으로 쓰고 있었다면 iPhone 기본 음성으로 돌아감.") }
        .onDisappear { model.stopSpeech() }
    }

    private var bases: [String] { draft.female ? VoiceLibrary.femaleBases : VoiceLibrary.maleBases }
    private var blendBinding: Binding<Float> { Binding(get: { 1 - draft.blend }, set: { draft.blend = 1 - $0 }) }
    private var rhythmBinding: Binding<Float> { Binding(get: { 1 - draft.rhythm }, set: { draft.rhythm = 1 - $0 }) }
    private var pauseBinding: Binding<Float> { Binding(get: { Float(draft.pause) }, set: { draft.pause = Double($0) }) }

    private func setGender(_ female: Bool) {
        guard female != draft.female else { return }
        draft.female = female
        let pool = female ? VoiceLibrary.femaleBases : VoiceLibrary.maleBases
        draft.base = pool[0]; draft.partner = pool[0]
    }
    private func label(_ id: String) -> String { (VoicePackManifest.names[id] ?? id) + " · " + (VoiceLibrary.baseTraits[id] ?? "") }

    private func baseCard(_ b: String) -> some View {
        let on = draft.base == b
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(VoicePackManifest.names[b] ?? b).font(.headline)
                Spacer(minLength: 4)
                Button { model.voice.audition(VoiceLibrary.base(b), text: "안녕하세요. \(VoicePackManifest.names[b] ?? b)입니다.") } label: {
                    Image(systemName: "play.circle.fill").font(.title3)
                }.buttonStyle(.plain).disabled(!pack.ready)
            }
            Text(VoiceLibrary.baseTraits[b] ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(10)
        .frame(width: 128, alignment: .leading)
        .background(on ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Color.accentColor : .clear, lineWidth: 2))
        .onTapGesture { draft.base = b; if !bases.contains(draft.partner) || draft.partner == b { draft.partner = b } }
    }

    private func slider(_ title: String, value: Binding<Float>, range: ClosedRange<Float>, format: @escaping (Float) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title); Spacer(); Text(format(value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range)
        }
    }
}

/// Ten vertical faders (±12 dB) with a live response curve.
struct EqualizerView: View {
    @Binding var gains: [Float]
    private let top: CGFloat = 8, bottom: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let layout = Layout(size: geo.size, top: top, bottom: bottom, count: VoiceProfile.bands.count)
            ZStack(alignment: .topLeading) {
                zeroLine(layout)
                responseCurve(layout)
                ForEach(0..<layout.count, id: \.self) { i in
                    fader(i, layout)
                }
            }
        }
    }

    private struct Layout {
        let size: CGSize, top: CGFloat, bottom: CGFloat, count: Int
        var column: CGFloat { size.width / CGFloat(count) }
        var track: CGFloat { size.height - top - bottom }
        var mid: CGFloat { top + track / 2 }
        func x(_ i: Int) -> CGFloat { column * (CGFloat(i) + 0.5) }
        func y(_ gain: Float) -> CGFloat { mid - CGFloat(gain) / 12 * track / 2 }
        func gain(atY y: CGFloat) -> Float { Float((mid - y) / (track / 2) * 12) }
    }

    private func zeroLine(_ l: Layout) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: l.mid))
            p.addLine(to: CGPoint(x: l.size.width, y: l.mid))
        }
        .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    private func responseCurve(_ l: Layout) -> some View {
        var path = Path()
        for i in 0..<l.count {
            let point = CGPoint(x: l.x(i), y: l.y(value(i)))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    private func fader(_ i: Int, _ l: Layout) -> some View {
        let x = l.x(i)
        let knobY = l.y(value(i))
        let label = VoiceProfile.bandLabels[i]
        return ZStack(alignment: .topLeading) {
            Capsule().fill(Color.secondary.opacity(0.18))
                .frame(width: 4, height: l.track)
                .position(x: x, y: l.mid)
            Circle().fill(Color.accentColor)
                .frame(width: 18, height: 18)
                .shadow(radius: 2)
                .position(x: x, y: knobY)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
                .position(x: x, y: l.size.height - 8)
            dragArea(i, l)
        }
    }

    private func dragArea(_ i: Int, _ l: Layout) -> some View {
        let drag = DragGesture(minimumDistance: 0).onChanged { g in
            let v: Float = l.gain(atY: g.location.y)
            let clamped: Float = max(-12, min(12, v))
            set(i, (clamped * 2).rounded() / 2)
        }
        let valueText = String(format: "%+.1f 데시벨", value(i))
        return Color.clear.contentShape(Rectangle())
            .frame(width: l.column, height: l.track + 16)
            .position(x: l.x(i), y: l.mid)
            .gesture(drag)
            .accessibilityElement()
            .accessibilityLabel(VoiceProfile.bandLabels[i] + " 헤르츠")
            .accessibilityValue(valueText)
            .accessibilityAdjustableAction { direction in
                let step: Float = direction == .increment ? 1 : -1
                set(i, max(-12, min(12, value(i) + step)))
            }
    }

    private func value(_ i: Int) -> Float { i < gains.count ? gains[i] : 0 }
    private func set(_ i: Int, _ v: Float) {
        var g = gains
        while g.count < VoiceProfile.bands.count { g.append(0) }
        g[i] = v
        gains = g
    }
}
