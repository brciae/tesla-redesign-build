import Foundation

@main struct GuidanceCardTests {
    static func main() {
        func check(_ value: Bool, _ message: String) { precondition(value, message) }
        check(GuidanceCardText.label("오크밸리1길 우회전", symbol: "", exitClock: 0) == "오크밸리1길 우회전", "Keep one short road and maneuver")
        check(GuidanceCardText.label("동작대교 · 국립현충원 · 강남역 · 서울역 · 한강대로 오른쪽 진출", symbol: "", exitClock: 0) == "동작대교 오른쪽 진출", "Keep one complete sign name instead of a long destination list")
        check(GuidanceCardText.label("매우 긴 이름을 가진 도로와 여러 목적지의 상세 설명 비보호 좌회전", symbol: "", exitClock: 0) == "비보호 좌회전", "Never lose the unprotected-turn restriction")
        check(GuidanceCardText.label("회전교차로에서 두 번째 출구로 진출", symbol: "arrow.triangle.2.circlepath", exitClock: 9) == "9시 방향 출구", "SDK clock direction is not an ordinal exit number")
        check(GuidanceCardText.label("1.3 km · 좌회전", symbol: "", exitClock: 0) == "1.3 km · 좌회전", "Keep next-turn distance when short")
        check(GuidanceCardText.label("길안내 업데이트 대기", symbol: "", exitClock: 0) == "길안내 업데이트 대기", "Keep stale status")
        check(GuidanceCardText.action("어떤 미확인 상태인지 아주 길게 이어지는 문구와 설명이 있음", symbol: "", exitClock: 0) == "진행 방향 확인", "Do not invent a turn from an unknown instruction")
        check(VehicleActivitySessionPolicy.shouldEnd(connected: true, guiding: false, previouslyGuiding: false, observationAge: 0), "Connection alone never starts or retains a card")
        check(VehicleActivitySessionPolicy.shouldEnd(connected: false, guiding: false, previouslyGuiding: false, observationAge: 10), "Idle card ends without reconnect grace")
        check(VehicleActivitySessionPolicy.shouldEnd(connected: true, guiding: false, previouslyGuiding: false, observationAge: 0), "Reconnection alone cannot retain an idle card")
        check(VehicleActivitySessionPolicy.shouldEnd(connected: false, guiding: false, previouslyGuiding: false, observationAge: 91), "Expired disconnected session ends")
        check(!VehicleActivitySessionPolicy.shouldEnd(connected: false, guiding: true, previouslyGuiding: false, observationAge: 0), "Guidance does not require a vehicle")
        check(VehicleActivitySessionPolicy.shouldEnd(connected: false, guiding: false, previouslyGuiding: true, observationAge: 0), "Explicit phone guidance end does not linger")
        check(VehicleActivitySessionPolicy.shouldEnd(connected: true, guiding: false, previouslyGuiding: true, observationAge: 0), "Guidance end removes idle card even while connected")
        check(!VehicleActivitySessionPolicy.shouldEnd(connected: false, guiding: false, previouslyGuiding: false, observationAge: 1000, charging: true), "Fleet-only charging survives BLE disconnect")
        check(!VehicleActivitySessionPolicy.shouldEnd(connected: false, guiding: false, previouslyGuiding: true, observationAge: 0, charging: true), "Guidance ending switches to active charging")
        check(VehicleActivitySessionPolicy.shouldEnd(connected: false, guiding: false, previouslyGuiding: false, observationAge: 0, previouslyCharging: true), "Explicit charging end removes a phone-only card immediately")
        check(!VehicleActivitySessionPolicy.shouldEnd(connected: false, guiding: true, previouslyGuiding: false, observationAge: 0, previouslyCharging: true), "Charging end must not remove active navigation")
        check(NavigationCardFormat.distance(150) == "150 m", "Metres remain precise")
        check(NavigationCardFormat.distance(1300) == "1.3 km", "Remaining route distance")
        check(NavigationCardFormat.distance(-1) == "—", "Unknown distance is not zero")
        let at = Date(timeIntervalSince1970: 1000)
        check(!NavigationCardFormat.stale(observedAt: at, now: at.addingTimeInterval(29)), "Fresh turn")
        check(NavigationCardFormat.stale(observedAt: at, now: at.addingTimeInterval(30)), "Old turn must hide")
        print("PASS: concise navigation labels, complete sign names, restrictions and roundabout direction")
    }
}
