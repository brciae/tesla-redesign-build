import SwiftUI

enum Page: String, Hashable {
    case controls = "컨트롤", climate = "실내 온도", charging = "충전"
    case security = "보안 및 운전자"
    case care = "차량 관리"
    case automation = "자동화", connection = "연결 상태", briefing = "오늘의 브리핑"
    case navigation = "카카오 내장 내비", preferences = "음성·내비 안내"
    case appearance = "차꾸미기"
    case fleetInsights = "차량 상세 데이터"
    case notifications = "알림 설정"
    case liveActivity = "잠금화면·아일랜드"
    case spotify = "Spotify 연결"
    case chargingSettings = "충전 계획·요금", recordSettings = "기록·백업"
    case parking = "주차 기록"
    case displaySettings = "화면·표시 단위"
    case releaseNotes = "릴리즈 노트"
    case character = "캐릭터"
}

struct GlassMenuCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0, content: content)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.fill(0.12).opacity(0.75))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.primary.opacity(0.18), Color.primary.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .padding(.bottom, 6)
    }
}

func glassMenuItem(_ page: Page, _ icon: String, title: String, subtitle: String?, colors: [Color], isLast: Bool = false) -> some View {
    VStack(spacing: 0) {
        NavigationLink(value: page) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                        .shadow(color: colors.first?.opacity(0.3) ?? .clear, radius: 4, x: 0, y: 2)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.35))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(MotionButtonStyle())

        if !isLast {
            Divider()
                .background(Color.primary.opacity(0.08))
                .padding(.leading, 64)
        }
    }
}


private struct SettingsMenuEntry: Identifiable {
    let page: Page
    let symbol: String
    let title: String
    let subtitle: String
    let colors: [Color]
    var id: Page { page }
    init(_ page: Page, _ symbol: String, _ title: String, _ subtitle: String, _ colors: [Color]) {
        self.page = page; self.symbol = symbol; self.title = title; self.subtitle = subtitle; self.colors = colors
    }
}
private struct SettingsMenuGroup: Identifiable {
    let title: String
    let items: [SettingsMenuEntry]
    var id: String { title }
}

/// Production menu and its destinations share one catalog; no duplicate links in unrelated groups.
struct SettingsMenuGroups: View {
    private let groups: [SettingsMenuGroup] = [
        .init(title: "안내·알림", items: [
            .init(.liveActivity, "rectangle.topthird.inset.filled", "잠금화면·아일랜드", "길안내 · 충전 카드 · 표시 상태", [.blue, .cyan]),
            .init(.preferences, "speaker.wave.2.fill", "음성·내비 안내", "목소리 · 안내 빈도 · 음량", [.blue, .cyan]),
            .init(.notifications, "bell.badge.fill", "알림 설정", "충전 알림 · 권한", [.purple, .blue])]),
        .init(title: "주행·충전", items: [
            .init(.navigation, "map", "내비게이션", "지도 · 위치 권한 · 하이패스", [.blue, .cyan]),
            .init(.chargingSettings, "bolt.fill", "충전 계획·요금", "충전 기준 · 전기 단가", [.green, .mint])]),
        .init(title: "차량 관리", items: [
            .init(.fleetInsights, "checkmark.shield", "차량 상태·보증", "사양 · 보증 · 경고", [.cyan, .blue]),
            .init(.care, "wrench.and.screwdriver.fill", "타이어·정비", "공기압 · 소모품 주기", [.orange, .yellow]),
            .init(.security, "shield.fill", "보안 및 운전자", "감시 모드 · 운전자", [.blue, .cyan])]),
        .init(title: "연결·기록", items: [
            .init(.connection, "antenna.radiowaves.left.and.right", "차량·NAS 연결", "계정 · 블루투스 · 서버", [.cyan, .blue]),
            .init(.spotify, "music.note", "Spotify 연결", "휴대폰 재생 정보 · 음악 제어", [.green, .mint]),
            .init(.recordSettings, "externaldrive", "기록·백업", "내보내기 · 복원", [.blue, .cyan])]),
        .init(title: "화면·꾸미기", items: [
            .init(.displaySettings, "textformat.size", "화면·표시 단위", "배경 · 거리 · 온도 단위", [.gray, .secondary]),
            .init(.appearance, "paintbrush.fill", "3D 차꾸미기", "외장 · 휠 · 실내", [.purple, .pink]),
            .init(.character, "figure.wave", "캐릭터", "3D 캐릭터 선택 · 미리보기", [.pink, .purple])]),
        .init(title: "자동화", items: [
            .init(.automation, "bolt.circle.fill", "스마트 자동화", "상황별 안내 · 자동 제어", [.green, .mint])]),
        .init(title: "앱 정보", items: [
            .init(.releaseNotes, "doc.text.fill", "릴리즈 노트", "버전별 변경 내역", [.orange, .pink])])
    ]
    var body: some View {
        VStack(spacing: 16) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.title).font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.primary.opacity(0.6)).padding(.leading, 6)
                    GlassMenuCard {
                        ForEach(group.items) { item in
                            glassMenuItem(item.page, item.symbol, title: item.title, subtitle: item.subtitle,
                                colors: item.colors, isLast: group.items.last?.page == item.page)
                        }
                    }
                }
            }
        }
    }
}
