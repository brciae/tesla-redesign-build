import SwiftUI
import PhotosUI

@MainActor
struct VehicleAppearanceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduced
    @ObservedObject private var store = VehicleAppearanceStore.shared
    @State private var draft = VehicleAppearance.original
    @State private var capturedKey = ""
    @State private var selection = "색상"
    @State private var camera = VehicleCameraCommand()
    @State private var photo: PhotosPickerItem?
    @State private var error: String?
    @State private var importedIDs = Set<String>()
    @State private var committedID: String?
    @State private var showingOriginal = false
    @FocusState private var editingPlate: Bool
    private var key: String { VehicleAppearanceStore.vehicleKey(vin: model.settings.string("vin"), demo: model.demo) }
    private var display: VehicleAppearance { showingOriginal ? .original : draft }
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                RealityVehicleView(runtime: model.runtime, presentation: ["allowInteraction": true, "animate": false, "states": [:]], command: camera, reducedMotion: reduced, appearance: display) { error = $0 }
                    .frame(height: 245).clipped().accessibilityLabel("차꾸미기 3D 미리보기. 좌우로 회전 가능")
                HStack {
                    Button(showingOriginal ? "꾸민 모습" : "원래 모델 비교") { showingOriginal.toggle() }
                    Spacer()
                    Button { camera.serial += 1; camera.action = "reset" } label: { Image(systemName: "arrow.counterclockwise") }.accessibilityLabel("시점 초기화")
                }.font(.subheadline)
                Picker("꾸미기 항목", selection: $selection) { ForEach(["색상", "틴팅", "인테리어", "번호판", "랩핑"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 20) {
                    if selection == "색상" { paintControls }
                    if selection == "틴팅" { tintControls }
                    if selection == "인테리어" { interiorControls }
                    if selection == "번호판" { plateControls }
                    if selection == "랩핑" { wrapControls }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                HStack { Image(systemName: "iphone"); Text("앱 표시만 변경 · 차량과 동기화되지 않음") }.font(.caption).foregroundStyle(Theme.muted)
                Button("원래 모델로 되돌리기") { draft = .original; showingOriginal = false }.buttonStyle(.bordered)
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            }.frame(maxWidth: 650).padding(.horizontal, 22).padding(.bottom, 30).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).background(Theme.bg).navigationTitle("차꾸미기").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("저장") { save() }.fontWeight(.semibold).accessibilityIdentifier("appearance.save") }
        }
        .onAppear { if capturedKey.isEmpty { capturedKey = key; draft = store.value(for: key) } }
        .onChange(of: key) { _, _ in error = "차량이 변경되어 편집을 종료함"; dismiss() }
        .onChange(of: selection) { _, _ in editingPlate = false }
        .onDisappear { store.discardUncommitted(importedIDs, keeping: committedID) }
        .task(id: photo) {
            guard let photo else { return }
            do {
                guard let data = try await photo.loadTransferable(type: Data.self), !Task.isCancelled, capturedKey == key else { return }
                let id = try store.importImage(data); importedIDs.insert(id); draft.imageID = id; draft.wrap = .image; edited()
            } catch { self.error = error.localizedDescription }
        }
    }
    private func edited() { draft.enabled = true; showingOriginal = false }
    private func save() {
        guard key == capturedKey else { error = "차량이 변경됨. 다시 열어야 함"; return }
        do { try store.save(draft, for: capturedKey); committedID = draft.validated().imageID; dismiss() }
        catch { self.error = error.localizedDescription }
    }
    private func color(_ path: WritableKeyPath<VehicleAppearance, String>) -> Binding<Color> {
        Binding(get: { Color(uiColor: UIColor(appearanceHex: draft[keyPath: path])) }, set: { draft[keyPath: path] = UIColor($0).appearanceHex; edited() })
    }
    private var paintControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(VehiclePaintPreset.modelYL.first { $0.hex == draft.paint }?.name ?? (draft.enabled ? "사용자 색상" : "원래 모델")).font(.title3.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 6) {
                ForEach(VehiclePaintPreset.modelYL) { preset in
                    Button { draft.paint = preset.hex; draft.finish = .gloss; edited() } label: {
                        Circle().fill(Color(uiColor: UIColor(appearanceHex: preset.hex)).gradient).frame(width: 34, height: 34)
                            .overlay(Circle().strokeBorder(.white.opacity(draft.paint == preset.hex && draft.enabled ? 1 : 0.2), lineWidth: draft.paint == preset.hex && draft.enabled ? 3 : 1)).padding(3)
                    }.buttonStyle(.plain).accessibilityLabel(preset.name).accessibilityAddTraits(draft.paint == preset.hex ? .isSelected : [])
                }
            }
            ColorPicker("자유 색상", selection: color(\.paint), supportsOpacity: false)
            Picker("마감", selection: $draft.finish) { ForEach(VehicleAppearance.Finish.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).onChange(of: draft.finish) { _, _ in edited() }
            Text("Model Y L 색상명 기준 · 실차 색감과 차이 가능").font(.caption).foregroundStyle(Theme.muted)
        }
    }
    private var tintControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("윈도 틴팅").font(.title3.weight(.semibold))
            HStack(spacing: 16) { ForEach(["101820", "302B26", "162D2B", "172C45", "332638"], id: \.self) { hex in
                Button { draft.tint = hex; edited() } label: { Circle().fill(Color(uiColor: UIColor(appearanceHex: hex))).frame(width: 40, height: 40).overlay(Circle().stroke(.white.opacity(draft.tint == hex ? 1 : 0.2), lineWidth: 2)) }.buttonStyle(.plain).accessibilityLabel("틴팅 색상 #" + hex)
            } }
            ColorPicker("자유 색상", selection: color(\.tint), supportsOpacity: false)
            HStack { Text("밝게"); Slider(value: $draft.tintStrength, in: 0...1).onChange(of: draft.tintStrength) { _, _ in edited() }; Text("어둡게") }
            Text("화면 농도 · 실차 투과율 아님 · 램프·미러 유지").font(.caption).foregroundStyle(Theme.muted)
        }
    }
    private var interiorControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(VehicleInteriorPreset.presets.first { $0.hex.uppercased() == draft.interiorColor.uppercased() }?.name ?? (draft.enabled ? "사용자 인테리어" : "올 블랙")).font(.title3.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                ForEach(VehicleInteriorPreset.presets) { preset in
                    Button {
                        draft.interiorColor = preset.hex
                        edited()
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(Color(uiColor: UIColor(appearanceHex: preset.hex)).gradient)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            .white.opacity(draft.interiorColor.uppercased() == preset.hex.uppercased() && draft.enabled ? 1 : 0.25),
                                            lineWidth: draft.interiorColor.uppercased() == preset.hex.uppercased() && draft.enabled ? 3 : 1
                                        )
                                )
                                .shadow(color: .black.opacity(0.35), radius: 3)

                            Text(preset.name)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.85))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.name)
                }
            }
            ColorPicker("자유 시트/내장 색상", selection: color(\.interiorColor), supportsOpacity: false)
            if let matched = VehicleInteriorPreset.presets.first(where: { $0.hex.uppercased() == draft.interiorColor.uppercased() }) {
                Text(matched.desc)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            } else {
                Text("사용자 정의 시트 색상 · 공조 화면과 실시간 연동됨")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
    }
    private var plateControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("번호판").font(.title3.weight(.semibold))
            TextField("예: 123가 4567", text: $draft.plate).textInputAutocapitalization(.characters).autocorrectionDisabled().textFieldStyle(.roundedBorder).focused($editingPlate).submitLabel(.done).onSubmit { editingPlate = false }.accessibilityIdentifier("appearance.plate").onChange(of: draft.plate) { _, value in draft.plate = String(value.prefix(12)); edited() }
            HStack(spacing: 16) { ForEach(["FFFFFF", "ACD9EF", "F2CA48", "286C50", "202124"], id: \.self) { hex in
                Button { draft.plateColor = hex; edited() } label: { RoundedRectangle(cornerRadius: 5).fill(Color(uiColor: UIColor(appearanceHex: hex))).frame(width: 43, height: 28).overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(draft.plateColor == hex ? 1 : 0.2), lineWidth: 2)) }.buttonStyle(.plain).accessibilityLabel("번호판 색상 #" + hex)
            } }
            ColorPicker("자유 색상", selection: color(\.plateColor), supportsOpacity: false)
            Text("앞·뒤 적용 · 기기 내 저장").font(.caption).foregroundStyle(Theme.muted)
        }
    }
    private var wrapControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("랩핑").font(.title3.weight(.semibold))
            Picker("패턴", selection: $draft.wrap) { ForEach(VehicleAppearance.Wrap.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).onChange(of: draft.wrap) { _, _ in edited() }
            if draft.wrap == .stripes || draft.wrap == .twoTone { ColorPicker("보조 색상", selection: color(\.accent), supportsOpacity: false) }
            if draft.wrap == .image {
                PhotosPicker(selection: $photo, matching: .images) { Label(draft.imageID == nil ? "랩핑 이미지 선택" : "다른 이미지 선택", systemImage: "photo") }.buttonStyle(.bordered)
                Text("앱 모델에 이미지를 투영함. Tesla 공식 전개도와 이 모델의 좌표가 달라 순정 랩핑 파일을 그대로 재현하지는 못함.").font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }
}
