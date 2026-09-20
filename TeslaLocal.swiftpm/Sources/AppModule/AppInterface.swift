import SwiftUI
import AVFoundation

struct VoiceSelectionControls: View {
    @Binding var identifier: String
    @Binding var style: String   // kept for call-site compatibility; the style picker lives in VoiceAdvancedControls

    var body: some View {
        Picker("안내 음성", selection: $identifier) {
            Text("한국어 · iPhone 기본").tag("")
            ForEach(VoiceLibrary.curated()) { choice in
                HStack(spacing: 10) {
                    VoicePortrait(url: choice.portrait, name: choice.name, size: 34)
                    VStack(alignment: .leading) {
                        Text(choice.name)
                        Text(choice.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }.tag(choice.id)
            }
            let mine = VoiceLibrary.customs
            if !mine.isEmpty {
                Section("내가 만든 음성") {
                    ForEach(mine) { p in Text(p.name).tag("offline:" + p.id) }
                }
            }
            if !selectionListed {
                Text(VoiceLibrary.label(for: identifier) + " (현재 선택)").tag(identifier)
            }
        }
        .accessibilityIdentifier("voice.profile")
    }

    private var selectionListed: Bool {
        if identifier.isEmpty { return true }
        if VoiceLibrary.curated().contains(where: { $0.id == identifier }) { return true }
        if identifier.hasPrefix("offline:custom:") { return true }
        return VoiceLibrary.systemChoices().contains { $0.id == identifier }
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

/// v34: everything that is not "which voice" lives here, under 고급.
struct VoiceAdvancedControls: View {
    @Binding var identifier: String
    @Binding var style: String
    @State private var allVoices = false
    var body: some View {
        Picker("말하기 스타일", selection: $style) {
            ForEach(BriefingStyle.allCases) { item in Text(item.title).tag(item.rawValue) }
        }.accessibilityIdentifier("voice.style")
        DisclosureGroup("모든 iPhone 음성", isExpanded: $allVoices) {
            Picker("iPhone 음성", selection: $identifier) {
                Text("iPhone 기본").tag("")
                ForEach(VoiceLibrary.systemChoices()) { choice in Text(choice.name + " · " + choice.detail).tag(choice.id) }
            }.pickerStyle(.inline).labelsHidden()
            InfoRow("음성 추가", "iPhone 설정 → 손쉬운 사용 → 콘텐츠 말하기 → 음성 → 한국어에서 프리미엄 음성을 내려받으면 여기 목록에 나타남.")
        }
    }
}

/// Form row whose explanation lives in an ⓘ popover instead of a paragraph under the control.
struct InfoRow: View {
    let title: String
    let text: String
    init(_ title: String, _ text: String) { self.title = title; self.text = text }
    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 4)
            InfoNote(title, text)
        }
    }
}

enum AppTab: Hashable { case vehicle, automation, settings }
private struct SelectAppTabKey: EnvironmentKey { static let defaultValue: (AppTab) -> Void = { _ in } }
extension EnvironmentValues {
    var selectAppTab: (AppTab) -> Void { get { self[SelectAppTabKey.self] } set { self[SelectAppTabKey.self] = newValue } }
}

/// Three independent navigation roots; driving mode is presented outside this container.
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
