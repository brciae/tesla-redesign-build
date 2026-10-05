import SwiftUI

struct CompanionToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduced
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 16) {
                configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Capsule().fill(configuration.isOn ? Color(uiColor: .systemGreen) : Color(uiColor: .systemGray4))
                    HStack {
                        if configuration.isOn { Text("I").font(.caption).foregroundStyle(.white.opacity(0.8)); Spacer(minLength: 0) }
                        Circle().fill(.white).frame(width: 30, height: 30).shadow(color: .black.opacity(0.16), radius: 2, y: 1)
                        if !configuration.isOn { Spacer(minLength: 0); Text("○").font(.caption).foregroundStyle(.white.opacity(0.5)) }
                    }.padding(.horizontal, 5)
                }.frame(width: 64, height: 38).accessibilityHidden(true)
            }.frame(minHeight: 48).contentShape(Rectangle()).opacity(enabled ? 1 : 0.45)
        }.buttonStyle(.plain)
            .accessibilityValue(configuration.isOn ? "켜짐" : "꺼짐")
            .animation(reduced ? nil : .easeInOut(duration: 0.18), value: configuration.isOn)
    }
}
import UIKit
import AVFoundation

struct VoiceSelectionControls: View {
    @Binding var identifier: String
    @Binding var style: String   // kept for call-site compatibility; the style picker lives in VoiceAdvancedControls

    var body: some View {
        Picker("안내 음성", selection: $identifier) {
            Section("타입캐스트 AI 고품질 음성") {
                ForEach(TypecastClient.presetVoices, id: \.id) { preset in
                    let label = "✨ \(preset.name) (\(preset.desc))"
                    let tagValue = "typecast:\(preset.id)"
                    Text(label).tag(tagValue)
                }
            }
            if !selectionListed {
                let custom = "\(customLabel(for: identifier)) (사용자 지정 Voice ID)"
                Text(custom).tag(identifier)
            }
        }
        .accessibilityIdentifier("voice.profile")
    }

    private var selectionListed: Bool {
        if identifier.hasPrefix("typecast:") {
            let vId = String(identifier.dropFirst(9)).trimmingCharacters(in: .whitespacesAndNewlines)
            return TypecastClient.presetVoices.contains(where: { $0.id == vId || $0.name == vId })
        }
        return false
    }

    private func customLabel(for id: String) -> String {
        if id.hasPrefix("typecast:") {
            let raw = String(id.dropFirst(9)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let char = TypecastCatalog.find(raw) {
                return "✨ \(char.nameKo) (\(char.desc))"
            }
            return "✨ " + raw
        }
        return "✨ " + id
    }
}


/// The character portrait beside a recorded voice. Falls back to the voice's initial so a pack that
/// ships without an image, or an engine voice, still lines up with the rest of the list.
struct VoicePortrait: View {
    let url: URL?
    let name: String
    var size: CGFloat = 34

    var body: some View {
        Group {
            if let url, let image = VoicePortrait.image(url) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.18)
                    Text(String(name.prefix(1))).font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    // Decoding the same few portraits on every redraw of a settings list is wasteful; they are tiny
    // and there are at most a handful, so keep them.
    private static var cache: [URL: UIImage] = [:]
    static func image(_ url: URL) -> UIImage? {
        if let hit = cache[url] { return hit }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache[url] = image
        return image
    }
}

/// Moderate, clean thumbnail portrait for Typecast AI and character voices.
/// Fits cleanly in pickers, status cards, and preset selection buttons without being overly huge.
struct TypecastVoiceThumbnail: View {
    let voice: String
    var size: CGFloat = 38
    /// v1.46: API voices have no portrait — draw a gender-coloured monogram instead of a blank.
    var gender: String? = nil
    private var palette: [Color] {
        switch gender ?? TypecastClient.shared.remoteVoices.first(where: { $0.nameKo == cleanName })?.gender {
        case "남성": return [Color(red: 0.15, green: 0.45, blue: 0.95), Color(red: 0.1, green: 0.75, blue: 0.75)]
        case "여성": return [Color(red: 0.95, green: 0.4, blue: 0.6), Color(red: 0.6, green: 0.35, blue: 0.95)]
        default: return [Color.gray, Color.blue.opacity(0.7)]
        }
    }

    var body: some View {
        Group {
            if let image = resolveImage() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: palette,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Text(String(cleanName.prefix(1)))
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
        .accessibilityHidden(true)
    }

    private var cleanName: String {
        voice.replacingOccurrences(of: "typecast:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveImage() -> UIImage? {
        let name = cleanName

        // 1. Direct Asset Catalog check by name
        if let img = UIImage(named: "typecast_portrait_\(name)") { return img }

        // 2. TypecastCatalog lookup (supports 131 Korean Female Young Adult characters!)
        if let char = TypecastCatalog.find(name) {
            // Check Asset Catalog by actor_id
            if let img = UIImage(named: "typecast_portrait_\(char.id)") { return img }
            // Check bundle resource path typecast_portraits/[actor_id].png
            if let path = Bundle.main.path(forResource: char.id, ofType: "png", inDirectory: "typecast_portraits"),
               let img = UIImage(contentsOfFile: path) {
                return img
            }
            if let resourceURL = Bundle.main.resourceURL {
                let direct = resourceURL.appendingPathComponent("typecast_portraits/\(char.id).png")
                if let img = UIImage(contentsOfFile: direct.path) { return img }
            }
        }

        // 3. English alias check
        let alias: String
        let folder: String
        switch name {
        case "은경": alias = "eunkyung"; folder = "yumi"
        case "서현": alias = "seohyun"; folder = "seohee"
        case "아엘": alias = "ael"; folder = "hyeonji"
        case "한영": alias = "hanyoung"; folder = "subin"
        default:
            if name.contains("은경") { alias = "eunkyung"; folder = "yumi" }
            else if name.contains("서현") { alias = "seohyun"; folder = "seohee" }
            else if name.contains("아엘") { alias = "ael"; folder = "hyeonji" }
            else if name.contains("한영") { alias = "hanyoung"; folder = "subin" }
            else { return nil }
        }
        if let img = UIImage(named: "typecast_portrait_\(alias)") { return img }

        // 4. Bundled resource folder fallback
        if let path = Bundle.main.path(forResource: "portrait", ofType: "png", inDirectory: "recorded/\(folder)"),
           let img = UIImage(contentsOfFile: path) {
            return img
        }
        if let resourceURL = Bundle.main.resourceURL {
            let direct = resourceURL.appendingPathComponent("recorded/\(folder)/portrait.png")
            if let img = UIImage(contentsOfFile: direct.path) { return img }
        }
        return nil
    }
}

/// v34: everything that is not "which voice" lives here, under 고급.
struct VoiceAdvancedControls: View {
    @Binding var identifier: String
    @Binding var style: String
    var body: some View {
        Picker("말하기 스타일", selection: $style) {
            ForEach(BriefingStyle.allCases) { item in Text(item.title).tag(item.rawValue) }
        }.accessibilityIdentifier("voice.style")
    }
}

/// Keep supporting information available without crowding the default form.
struct InfoRow: View {
    let title: String
    let text: String
    init(_ title: String, _ text: String) { self.title = title; self.text = text }
    var body: some View {
        DisclosureGroup(title) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct VoiceCacheRow: View {
    let entry: TypecastClient.VoiceCacheEntry
    var delete: () -> Void
    @State private var confirming = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text("\(entry.count)개 · \(String(format: "%.1f", entry.megabytes))MB").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("삭제", role: .destructive) { confirming = true }
                .font(.caption.weight(.semibold)).buttonStyle(.bordered).controlSize(.small)
                .confirmationDialog("\(entry.name) 음성 캐시를 삭제할까요?", isPresented: $confirming, titleVisibility: .visible) {
                    Button("\(entry.name) 캐시 삭제", role: .destructive, action: delete)
                    Button("취소", role: .cancel) {}
                } message: { Text("다른 음성의 캐시는 그대로 남습니다. 이 음성은 다음 재생 때 다시 합성됩니다.") }
        }
        .padding(.vertical, 4)
    }
}

/// v1.46: one voice's cache, grouped by what the sentence is about; pick single clips or whole groups to delete.
struct VoiceCacheDetailView: View {
    let entry: TypecastClient.VoiceCacheEntry
    @ObservedObject private var typecast = TypecastClient.shared
    @State private var items: [TypecastClient.CachedPhrase] = []
    @State private var selection = Set<URL>()
    @State private var editMode: EditMode = .inactive
    @State private var confirmGroup: String?
    @State private var confirmSelected = false
    private var groups: [(String, [TypecastClient.CachedPhrase])] {
        Dictionary(grouping: items, by: \.group).map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }
    var body: some View {
        List(selection: $selection) {
            ForEach(groups, id: \.0) { group, phrases in
                Section {
                    ForEach(phrases) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.text.isEmpty ? "(문구 기록 없음)" : p.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                            Text("\(p.kilobytes)KB · \(p.date.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                        }.tag(p.id)
                    }
                } header: {
                    HStack {
                        Text("\(group) · \(phrases.count)개")
                        Spacer()
                        Button("그룹 삭제", role: .destructive) { confirmGroup = group }.font(.caption.weight(.semibold))
                    }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode.isEditing ? "완료" : "선택") { withAnimation { editMode = editMode.isEditing ? .inactive : .active; selection.removeAll() } }
            }
            ToolbarItem(placement: .bottomBar) {
                if editMode.isEditing {
                    Button("선택한 \(selection.count)개 삭제", role: .destructive) { confirmSelected = true }.disabled(selection.isEmpty)
                }
            }
        }
        .confirmationDialog("선택한 캐시를 삭제할까요?", isPresented: $confirmSelected, titleVisibility: .visible) {
            Button("\(selection.count)개 삭제", role: .destructive) { delete(items.filter { selection.contains($0.id) }) }
        } message: { Text("삭제한 문구는 다음 재생 때 다시 합성됩니다.") }
        .confirmationDialog("\(confirmGroup ?? "") 그룹을 모두 삭제할까요?", isPresented: Binding(get: { confirmGroup != nil }, set: { if !$0 { confirmGroup = nil } }), titleVisibility: .visible) {
            Button("그룹 삭제", role: .destructive) { if let g = confirmGroup { delete(items.filter { $0.group == g }) } }
        }
        .onAppear(perform: reload)
    }
    private func reload() { items = typecast.cachedPhrases(voice: entry.id) }
    private func delete(_ list: [TypecastClient.CachedPhrase]) {
        typecast.deleteCached(list); selection.removeAll(); reload()
    }
}

struct VoiceCacheDeleteButton: View {
    var delete: () -> Void
    @State private var confirming = false
    var body: some View {
        Button("전체 캐시 비우기") { confirming = true }
            .font(.caption)
            .foregroundStyle(.red)
            .buttonStyle(.borderless)
            .accessibilityIdentifier("voice.cache.delete")
            .confirmationDialog("모든 음성의 저장된 캐시를 삭제할까요?", isPresented: $confirming, titleVisibility: .visible) {
                Button("모든 음성 캐시 삭제", role: .destructive, action: delete)
                Button("취소", role: .cancel) {}
            } message: {
                Text("음성을 바꿔도 캐시는 유지됩니다. 삭제 후 다시 합성하면 API 사용량이 발생할 수 있습니다.")
            }
    }
}

enum AppTab: Hashable {
    case home, controls, energy, drive, menu
    case vehicle, automation, settings
}
private struct SelectAppTabKey: EnvironmentKey { static let defaultValue: (AppTab) -> Void = { _ in } }
extension EnvironmentValues {
    var selectAppTab: (AppTab) -> Void { get { self[SelectAppTabKey.self] } set { self[SelectAppTabKey.self] = newValue } }
}

/// Three independent navigation roots; used by InterfaceProbe test fixture
struct AppTabScaffold<Vehicle: View, Automation: View, Settings: View>: View {
    @Binding var selection: AppTab
    @ViewBuilder var vehicle: () -> Vehicle
    @ViewBuilder var automation: () -> Automation
    @ViewBuilder var settings: () -> Settings
    var body: some View {
        TabView(selection: $selection) {
            vehicle().tabItem { Label("차량", systemImage: "car.fill") }.tag(AppTab.vehicle)
            automation().tabItem { Label("자동화", systemImage: "bolt.circle") }.tag(AppTab.automation)
            settings().tabItem { Label("설정", systemImage: "gearshape") }.tag(AppTab.settings)
        }
        .environment(\.selectAppTab, { selection = $0 })
    }
}

/// 5 primary navigation roots matching commercial EV app standards; driving mode is presented outside this container.
struct Commercial5TabScaffold<Home: View, Controls: View, Energy: View, Drive: View, Menu: View>: View {
    @Binding var selection: AppTab
    @AppStorage("tabBarOpacity") private var tabBarOpacity = 1.0
    @ViewBuilder var home: () -> Home
    @ViewBuilder var controls: () -> Controls
    @ViewBuilder var energy: () -> Energy
    @ViewBuilder var drive: () -> Drive
    @ViewBuilder var menu: () -> Menu
    var body: some View {
        TabView(selection: $selection) {
            styled(home()).tabItem { Label("홈", systemImage: "car.fill") }.tag(AppTab.home)
            styled(controls()).tabItem { Label("컨트롤", systemImage: "slider.horizontal.2.square.on.square") }.tag(AppTab.controls)
            styled(energy()).tabItem { Label("에너지", systemImage: "bolt.fill") }.tag(AppTab.energy)
            styled(drive()).tabItem { Label("운행", systemImage: "map.fill") }.tag(AppTab.drive)
            styled(menu()).tabItem { Label("메뉴", systemImage: "ellipsis.circle.fill") }.tag(AppTab.menu)
        }
        .environment(\.selectAppTab, { selection = $0 })
    }

    private func styled<Content: View>(_ content: Content) -> some View {
        content
            .safeAreaPadding(.bottom, 8)
            .toolbarBackground(Theme.adaptive(dark: UIColor(white: 0.12, alpha: 1), light: UIColor.white).opacity(min(1, max(0.5, tabBarOpacity))), for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
    }
}

/// Form/List's automatic row action must never combine Preview and Stop.
struct VoicePreviewControls: View {
    var previewTitle = "음성 미리 듣기"
    var preview: () -> Void
    var stop: () -> Void
    var body: some View {
        HStack {
            Button(action: preview) { Label(previewTitle, systemImage: "play.fill").frame(minHeight: 44) }
                .buttonStyle(.borderless).accessibilityIdentifier("voice.preview")
            Spacer()
            Button(action: stop) { Label("중지", systemImage: "stop.fill").frame(minHeight: 44) }
                .buttonStyle(.borderless).accessibilityIdentifier("voice.stop")
        }
    }
}
