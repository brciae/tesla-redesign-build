import SwiftUI

/// v1.31: per-version change log shown under 메뉴 → 릴리즈 노트. Add a new entry at the top on every build.
struct ReleaseNote: Identifiable {
    let version: String
    let date: String
    let items: [String]
    var id: String { version }
}

enum ReleaseNotes {
    static let all: [ReleaseNote] = [
        ReleaseNote(version: "1.35 (135)", date: "2026-10-02", items: [
            "길안내: '분기후 합류 방면, 분기 후 합류 구간입니다'처럼 안내 용어(분기·합류·진출 등)를 지명으로 읽던 문제 수정 — 지명이 아닌 방면 이름은 음성·화면 모두에서 제외",
            "길안내: 분기 후 합류 안내를 '도로가 갈라졌다가 다시 합쳐지는 구간입니다. 차로를 유지하세요.'로 변경",
            "안전 안내: '구간 단속 구간입니다' → '구간 단속 중입니다. 제한 속도를 지키세요.'",
            "안전 안내: 어린이 보호구역·버스 전용 차로 안내를 행동 지시까지 포함한 완전한 문장으로 변경",
        ]),
        ReleaseNote(version: "1.34 (134)", date: "2026-10-02", items: [
            "말줄임표(…) 전수 제거: 글자 60여 곳을 잘라내는 대신 칸에 맞게 글자 크기를 줄이도록 변경 (대시보드·홈·기록·배터리 등 전체)",
            "설정 → 내비 안내: '과속 경고음' 켜기/끄기, 경고음 음량 슬라이더, 미리 듣기 추가",
            "과속 경고음을 음량 조절이 가능한 전용 소리로 변경",
            "Typecast 음성 캐시를 캐릭터(목소리)별로 저장하고, 설정에서 캐릭터별로 골라 삭제 가능",
            "기존(1.34 이전) 캐시는 '미분류'로 묶여 따로 삭제 가능하며, 재생될 때마다 해당 캐릭터 폴더로 자동 정리",
        ]),
        ReleaseNote(version: "1.33 (133)", date: "2026-10-02", items: [
            "충전 시작 시간대: 막대가 아예 안 그려지던 문제 수정, 시간별 막대 + 심야/주간 색 구분",
            "최근 6개월 추이: 항상 6개월 칸 표시, 월별 합계 kWh를 막대 위에 표시",
            "배터리 잔량 추이: 데이터 사이를 부드럽게 꾸며 그리던 가짜 곡선 제거(직선 연결), 6시간 이상 기록 공백은 선을 끊어 표시, 20% 경고선 추가",
        ]),
        ReleaseNote(version: "1.32 (132)", date: "2026-10-02", items: [
            "3D 캐릭터가 금속처럼 번쩍이던 문제 수정 (모델 변환 시 금속도 100%로 잘못 들어간 재질을 무광 피부·옷 재질로 교정)",
        ]),
        ReleaseNote(version: "1.31 (131)", date: "2026-10-02", items: [
            "과속 경고: 제한속도를 넘으면 속도 숫자가 빨간색으로 바뀜",
            "과속 경고: 10km/h 이상 초과 시 화면 가장자리 붉은 점멸과 2초 간격 경고음",
            "과속 경고: 20km/h 이상 초과 시 더 빠른 점멸과 0.8초 간격 경고음",
            "클러스터: 하단 도착 정보 카드의 배터리 %가 '3…'처럼 잘리던 문제 수정",
            "메뉴에 릴리즈 노트 추가 (이 화면)",
        ]),
        ReleaseNote(version: "1.30 (130)", date: "2026-10-02", items: [
            "실내 공조: 차량 이미지에서 실제로 없는 3열 문 제거, 검은 배경 제거(라이트 모드 흰 배경)",
            "실내 공조: 'Model Y L · 6인승' 제목이 차량을 가리지 않도록 위로 분리",
            "러닝 테마: 세로·가로 배치 재정리, 지도가 안내 카드를 덮던 문제 수정",
            "러닝 테마: 3D 캐릭터를 불러오지 못하면 원인을 화면에 표시",
        ]),
        ReleaseNote(version: "1.29 (129)", date: "2026-10-02", items: [
            "3D 차량: 운전석 문을 열면 조수석 문이 열리던 좌우 반전 수정",
            "안정성: 차량·BLE에서 비정상 숫자(NaN·무한대)가 오면 앱이 종료되던 문제 차단",
        ]),
        ReleaseNote(version: "1.28 (128)", date: "2026-10-02", items: [
            "3D 리깅 캐릭터 도입 (Mixamo 모션캡처): 대기·걷기·뛰기가 속도에 따라 자연스럽게 전환",
            "러닝 테마 가로 모드: 드래그해서 캐릭터를 옆·뒤에서 보기, 두 번 탭하면 원위치",
            "캐릭터 도우미 채팅 화면에 3D 캐릭터 표시",
        ]),
        ReleaseNote(version: "1.27 (127)", date: "2026-10-01", items: [
            "러닝 캐릭터 고화질·72fps 재생",
            "캐릭터 도우미 채팅 추가 (차량 데이터 기반 답변 + Typecast 음성)",
        ]),
        ReleaseNote(version: "1.26 (126)", date: "2026-10-01", items: [
            "컨트롤: 흰 배경 3D 차량, 조작 시 해당 부위로 카메라 이동",
            "컨트롤: 중복 선택 메뉴 제거",
            "충전 애니메이션 2배 빠르게",
            "기록: 충전 단가를 사용자가 입력한 요금(집 210원, 슈퍼차저 339원) 기준으로 계산",
            "기록: 시작 시간대 차트 범례·라벨 추가, 6개월 막대 차트 개선",
        ]),
        ReleaseNote(version: "1.24–1.25", date: "2026-09-30", items: [
            "대시보드: 테마 변경·회전 시 종료되던 문제 방지",
            "대시보드: 화면 회전 잠금과 관계없이 폰 기울기에 따라 자동 가로·세로 전환",
            "대시보드: 상단 메뉴가 화면 맨 위에서 내려오도록 수정",
            "내비: 내 차 아이콘 크기 조절 (기본 2배, 1~3배)",
            "러닝 테마: 밝은 테마, 위 캐릭터 · 아래 정보 배치",
        ]),
        ReleaseNote(version: "1.20–1.23", date: "2026-09-29", items: [
            "음성 안내: '주의하세요.'처럼 불완전한 문장을 모두 완전한 문장으로 수정",
            "음성 안내: 문장 끝이 잘리지 않도록 음성 뒤에 여유 추가",
        ]),
    ]
}

struct ReleaseNotesView: View {
    private var current: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(v) (\(b))"
    }
    var body: some View {
        List {
            Section { LabeledContent("설치된 버전", value: current) }
            ForEach(ReleaseNotes.all) { note in
                Section {
                    ForEach(note.items, id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle.fill").font(.subheadline)
                            .labelStyle(.titleAndIcon).symbolRenderingMode(.hierarchical)
                    }
                } header: {
                    HStack { Text("v" + note.version).font(.headline); Spacer(); Text(note.date).font(.caption) }
                }
            }
        }
        .navigationTitle("릴리즈 노트")
    }
}
