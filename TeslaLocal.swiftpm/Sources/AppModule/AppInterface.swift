import SwiftUI
import AVFoundation

struct VoiceSelectionControls: View {
    @Binding var identifier: String
    @Binding var style: String   // kept for call-site compatibility; the style picker lives in VoiceAdvancedControls

    var body: some View {
        Picker("안내 음성", selection: $identifier) {
            Section("타입캐스트 AI 고품질 음성") {
                ForEach(TypecastClient.presetVoices, id: \.id) { preset in
                    Text("✨ " + preset.name + " (" + preset.desc + ")").tag("typecast:" + preset.id)
                }
            }
            if !selectionListed {
                Text(customLabel(for: identifier) + " (사용자 지정 Voice ID)").tag(identifier)
            }
        }
        .accessibilityIdentifier("voice.profile")
    }

    private var selectionListed: Bool {
        if identifier.hasPrefix("typecast:") {
            let vId = String(identifier.dropFirst(9))
            return TypecastClient.presetVoices.contains(where: { $0.id == vId })
        }
        return false
    }

    private func customLabel(for id: String) -> String {
        if id.hasPrefix("typecast:") {
            return "✨ " + String(id.dropFirst(9))
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

/// Form row explanation placeholder: renders EmptyView to keep settings forms clean.
struct InfoRow: View {
    let title: String
    let text: String
    init(_ title: String, _ text: String) { self.title = title; self.text = text }
    var body: some View {
        EmptyView()
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
    @ViewBuilder var home: () -> Home
    @ViewBuilder var controls: () -> Controls
    @ViewBuilder var energy: () -> Energy
    @ViewBuilder var drive: () -> Drive
    @ViewBuilder var menu: () -> Menu
    var body: some View {
        TabView(selection: $selection) {
            home().tabItem { Label("홈", systemImage: "car.fill") }.tag(AppTab.home)
            controls().tabItem { Label("컨트롤", systemImage: "slider.horizontal.2.square.on.square") }.tag(AppTab.controls)
            energy().tabItem { Label("에너지", systemImage: "bolt.fill") }.tag(AppTab.energy)
            drive().tabItem { Label("운행", systemImage: "map.fill") }.tag(AppTab.drive)
            menu().tabItem { Label("메뉴", systemImage: "ellipsis.circle.fill") }.tag(AppTab.menu)
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
