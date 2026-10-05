//
//  TypecastCharacterPickerSheet.swift
//  YLCompanion
//
//  Sheet to browse and select from 131 Typecast Korean Female Young Adult voices.
//
import SwiftUI

struct TypecastCharacterPickerSheet: View {
    /// v1.48: the same browser picks either the app's guidance voice or the floating character's own voice.
    enum Target { case app, floatingCharacter }
    var target: Target = .app
    @AppStorage("characterFloat.voice") private var floatVoice = ""
    @State private var previewing: String?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var typecast = TypecastClient.shared

    @State private var searchQuery = ""
    // v1.46: filters survive the list refreshing underneath (they used to snap back to 전체 after the sync).
    @AppStorage("typecast.filter.category") private var selectedCategory = "전체"
    @AppStorage("typecast.filter.gender") private var selectedGender = "전체"
    @AppStorage("typecast.filter.age") private var selectedAge = "전체"
    private let genders = ["전체", "여성", "남성"]
    private let ages = ["전체", "어린이", "청소년", "청년", "중년", "노년"]

    /// v1.42: bundled curated voices + every voice the account can use from the Typecast API.
    private var pool: [TypecastCharacter] {
        let bundled = TypecastCatalog.characters
        let names = Set(bundled.map { $0.nameKo.lowercased() })
        return bundled + typecast.remoteVoices.filter { !names.contains($0.nameKo.lowercased()) }.sorted { $0.nameKo < $1.nameKo }
    }

    /// v1.48: genres come from the voices themselves (Typecast use_cases), not a fixed short list.
    private static let useCaseKo: [String: String] = [
        "Conversational": "대화", "Announcer": "아나운서", "News": "뉴스", "Audiobook": "오디오북", "Storytelling": "스토리텔링",
        "Radio/Podcast": "라디오·팟캐스트", "Radio": "라디오", "Podcast": "팟캐스트", "Ads": "광고", "Ad": "광고", "Advertisement": "광고",
        "Promotion": "홍보", "Event": "이벤트", "Game": "게임", "Games": "게임", "Gaming": "게임", "Animation": "애니메이션", "Anime": "애니메이션",
        "Music": "음악", "Singing": "노래", "Entertainment": "엔터테인먼트", "Education": "교육", "E-learning": "이러닝", "E-Learning": "이러닝",
        "Documentary": "다큐멘터리", "Meditation": "명상", "Kids": "키즈", "Children": "어린이", "Customer Service": "고객 상담",
        "Voice Assistant": "음성 비서", "Assistant": "비서", "Character": "캐릭터", "Drama": "드라마", "Movie": "영화", "Film": "영화",
        "Trailer": "예고편", "ASMR": "ASMR", "Sports": "스포츠", "Narration": "내레이션", "Tutorial": "튜토리얼", "Corporate": "기업",
        "Comedy": "코미디", "Horror": "공포", "Vlog": "브이로그", "Social Media": "SNS", "YouTube": "유튜브", "Shorts": "쇼츠", "Webtoon": "웹툰",
    ]
    static func uses(_ c: TypecastCharacter) -> [String] {
        c.category.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    static func label(_ raw: String) -> String { raw == "전체" ? "전체" : (useCaseKo[raw] ?? raw) }
    private var categories: [String] {
        var count: [String: Int] = [:]
        for c in pool { for u in Self.uses(c) { count[u, default: 0] += 1 } }
        return ["전체"] + count.keys.sorted { (count[$0]!, Self.label($1)) > (count[$1]!, Self.label($0)) }
    }
    private func matches(_ c: TypecastCharacter, category: String) -> Bool { category == "전체" || Self.uses(c).contains(category) }

    private var filteredCharacters: [TypecastCharacter] {
        TypecastCatalog.search(query: searchQuery, gender: selectedGender, age: selectedAge, in: pool).filter { matches($0, category: selectedCategory) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LocalBriefingControls(title: "타입캐스트 캐릭터 선택") {
                    ["선택 음성 \(TypecastCatalog.find(typecast.selectedVoiceId)?.nameKo ?? "사용자 지정 음성").", "\(Self.label(selectedCategory)) 분류에서 \(filteredCharacters.count)개가 검색됐습니다."]
                }
                // Category Pills
                VStack(spacing: 6) {
                    pills(genders, selection: $selectedGender) { TypecastCatalog.search(query: "", gender: $0, in: pool).count }
                    pills(ages, selection: $selectedAge) { TypecastCatalog.search(query: "", gender: selectedGender, age: $0, in: pool).count }
                    categoryPills
                }
                    .padding(.vertical, 8)
                    .background(Color(UIColor.secondarySystemBackground))

                // Character List / Grid
                if filteredCharacters.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "person.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("검색된 캐릭터가 없습니다.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        Section {
                            ForEach(filteredCharacters) { char in
                                characterRow(char)
                            }
                        } header: {
                            Text("캐릭터 (\(filteredCharacters.count)명)")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("타입캐스트 캐릭터 선택")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "이름, 분위기, 톤 검색 (예: 나윤, 차분한, 중음)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
            .onDisappear { if previewing != nil { typecast.stop(); previewing = nil } }
            .task {
                await typecast.refreshVoiceCatalog(quiet: true)
                if !typecast.remoteVoices.isEmpty, !categories.contains(selectedCategory) { selectedCategory = "전체" } // pre-1.48 fixed labels
            }
        }
    }

    // MARK: - Category Filter Pills

    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    let isSelected = selectedCategory == cat
                    let count = TypecastCatalog.search(query: "", gender: selectedGender, age: selectedAge, in: pool).filter { matches($0, category: cat) }.count
                    Button {
                        selectedCategory = cat
                    } label: {
                        HStack(spacing: 4) {
                            Text(Self.label(cat))
                            Text("(\(count))")
                                .font(.caption2)
                                .opacity(0.8)
                        }
                        .font(.subheadline.weight(isSelected ? .bold : .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isSelected ? Color.blue : Color(UIColor.systemBackground), in: Capsule())
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .overlay(Capsule().stroke(Color.primary.opacity(isSelected ? 0 : 0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func pills(_ items: [String], selection: Binding<String>, count: @escaping (String) -> Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    let on = selection.wrappedValue == item
                    Button { selection.wrappedValue = item } label: {
                        HStack(spacing: 4) { Text(item); Text("(\(count(item)))").font(.caption2).opacity(0.8) }
                            .font(.subheadline.weight(on ? .bold : .medium))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(on ? Color.blue : Color(UIColor.systemBackground), in: Capsule())
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .overlay(Capsule().stroke(Color.primary.opacity(on ? 0 : 0.12), lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 16)
        }
    }

    // MARK: - Character Row

    private func characterRow(_ char: TypecastCharacter) -> some View {
        let current = target == .floatingCharacter ? floatVoice : typecast.selectedVoiceId
        let isSelected = current == char.nameKo || current == char.id || current == char.nameEn

        return HStack(spacing: 12) {
            // Face Portrait Thumbnail
            TypecastVoiceThumbnail(voice: char.nameKo, size: 44, gender: char.gender)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(char.nameKo)
                        .font(.body.weight(.bold))
                        .foregroundStyle(.primary)

                    Text(char.nameEn)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if char.isCuratedPreset {
                        Text("★ 추천")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }

                Text(char.desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.5)
            }

            Spacer()

            // v1.36: listen before choosing — plays a short sample in this character's voice.
            Button {
                if previewing == char.nameKo { typecast.stop(); previewing = nil }
                else {
                    previewing = char.nameKo
                    if !char.previewURL.isEmpty {
                        typecast.playPreview(char.previewURL) { DispatchQueue.main.async { if previewing == char.nameKo { previewing = nil } } }
                    } else { typecast.testSpeech(text: "안녕하세요, \(char.nameKo)입니다. 300미터 앞에서 우회전하세요.", voiceId: char.nameKo) {
                        DispatchQueue.main.async { if previewing == char.nameKo { previewing = nil } }
                    } }
                }
            } label: {
                Image(systemName: previewing == char.nameKo ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(previewing == char.nameKo ? Color.red : Color.blue)
            }
            .buttonStyle(.plain)
            .disabled(!typecast.hasKey)
            .accessibilityLabel(previewing == char.nameKo ? "\(char.nameKo) 미리듣기 정지" : "\(char.nameKo) 목소리 미리듣기")

            // Select Button
            Button {
                selectCharacter(char)
            } label: {
                if isSelected {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("사용 중")
                    }
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.18), in: Capsule())
                    .foregroundStyle(.green)
                } else {
                    Text("선택")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
    }

    private func selectCharacter(_ char: TypecastCharacter) {
        typecast.stop(); previewing = nil
        if target == .floatingCharacter {
            floatVoice = char.nameKo
            model.voice.say("안녕하세요, 이제 제가 이 목소리로 말할게요.", category: "voiceControl", manual: true, voice: char.nameKo)
            dismiss(); return
        }
        typecast.selectedVoiceId = char.nameKo
        UserDefaults.standard.set("typecast:\(char.nameKo)", forKey: "voiceIdentifier")
        model.voice.say("\(char.nameKo) 음성을 선택했습니다.", category: "voiceControl", manual: true)
        dismiss()
    }
}
