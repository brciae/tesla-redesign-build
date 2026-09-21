import SwiftUI

/// v31: the home screen is a list of modules the user can show, hide and reorder,
/// so the app opens with only the things that person actually uses.
enum HomeModule: String, CaseIterable, Identifiable {
    case automation, appearance, controls, climate, location, charging, schedule, security
    case trips, battery, drive, navigation, care, preferences, connection

    var id: String { rawValue }

    var page: Page {
        switch self {
        case .automation: return .automation
        case .appearance: return .appearance
        case .controls: return .controls
        case .climate: return .climate
        case .location: return .location
        case .charging: return .charging
        case .schedule: return .schedule
        case .security: return .security
        case .trips: return .trips
        case .battery: return .battery
        case .drive: return .drive
        case .navigation: return .navigation
        case .care: return .care
        case .preferences: return .preferences
        case .connection: return .connection
        }
    }

    /// Control side (the car right now) or records side (history and settings).
    var isControl: Bool {
        switch self {
        case .automation, .appearance, .controls, .climate, .location, .charging, .schedule, .security: return true
        default: return false
        }
    }

    var title: String {
        switch self {
        case .battery: return "배터리 분석·충전 기록"
        default: return page.rawValue
        }
    }

    var icon: String {
        switch self {
        case .automation: return "bolt.circle"
        case .appearance: return "paintpalette"
        case .controls: return "car.front.waves.up"
        case .climate: return "fanblades.fill"
        case .location: return "location.north"
        case .charging: return "bolt.fill"
        case .schedule: return "alarm"
        case .security: return "checkmark.shield.fill"
        case .trips: return "point.topleft.down.to.point.bottomright.curvepath"
        case .battery: return "chart.xyaxis.line"
        case .drive: return "speedometer"
        case .navigation: return "map"
        case .care: return "wrench.and.screwdriver.fill"
        case .preferences: return "slider.horizontal.3"
        case .connection: return "antenna.radiowaves.left.and.right"
        }
    }

    var subtitle: String {
        switch self {
        case .automation: return "자동화 룰 · Siri 단축어"
        case .appearance: return "차량 색상 · 틴팅 · 번호판"
        case .controls: return "도어 · 트렁크 · 라이트"
        case .climate: return "온도 조절 · 공조 제어"
        case .location: return "차량 위치 · 스마트 주차"
        case .charging: return "충전 제어 · 목표량 설정"
        case .schedule: return "출발 알림 · 브리핑 일정"
        case .security: return "차량 보안 · 키 관리"
        case .trips: return "주행 기록 · 전비 · 브리핑"
        case .battery: return "배터리 헬스 · 충전 이력"
        case .drive: return "실시간 주행 정보"
        case .navigation: return "길안내 · 외부 내비 연동"
        case .care: return "주차 위치 · 정비 기록"
        case .preferences: return "단위 · 음성 안내 · 시스템"
        case .connection: return "BLE 연결 진단 · 백업"
        }
    }
}

@MainActor
final class HomeLayoutStore: ObservableObject {
    static let shared = HomeLayoutStore()
    private static let key = "homeModules"
    static let defaults: [HomeModule] = [.automation, .location, .charging, .climate, .controls, .trips, .battery, .care, .preferences]

    @Published private(set) var shown: [HomeModule] = []

    private init() { shown = Self.load() }

    var hidden: [HomeModule] { HomeModule.allCases.filter { !shown.contains($0) } }

    private static func load() -> [HomeModule] {
        guard let saved = UserDefaults.standard.array(forKey: key) as? [String] else { return defaults }
        let list = saved.compactMap(HomeModule.init(rawValue:))
        return list.isEmpty ? defaults : list
    }
    private func save() { UserDefaults.standard.set(shown.map(\.rawValue), forKey: Self.key) }

    func show(_ module: HomeModule) {
        guard !shown.contains(module) else { return }
        shown.append(module); save()
    }
    func hide(_ module: HomeModule) {
        shown.removeAll { $0 == module }; save()
    }
    func move(from source: IndexSet, to destination: Int) {
        shown.move(fromOffsets: source, toOffset: destination); save()
    }
    func reset() { shown = Self.defaults; save() }
}

/// Show / hide / reorder sheet for the home screen.
struct HomeLayoutEditor: View {
    @ObservedObject private var store = HomeLayoutStore.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("홈에 표시") {
                    ForEach(store.shown) { module in
                        HStack {
                            Label(module.title, systemImage: module.icon)
                            Spacer(minLength: 4)
                            Button { store.hide(module) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.orange) }
                                .buttonStyle(.plain).accessibilityLabel(module.title + " 숨기기")
                        }
                    }
                    .onMove { store.move(from: $0, to: $1) }
                    if store.shown.isEmpty { Text("표시할 항목을 아래에서 추가").foregroundStyle(.secondary) }
                }
                Section("숨김") {
                    ForEach(store.hidden) { module in
                        HStack {
                            Label(module.title, systemImage: module.icon).foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Button { store.show(module) } label: { Image(systemName: "plus.circle.fill") }
                                .buttonStyle(.plain).accessibilityLabel(module.title + " 표시")
                        }
                    }
                    if store.hidden.isEmpty { Text("모두 표시 중").foregroundStyle(.secondary) }
                }
                Section {
                    Button("기본 구성으로 되돌리기") { store.reset() }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("홈 메뉴 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
    }
}
