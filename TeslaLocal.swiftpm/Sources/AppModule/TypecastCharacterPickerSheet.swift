//
//  TypecastCharacterPickerSheet.swift
//  YLCompanion
//
//  Sheet to browse and select from 131 Typecast Korean Female Young Adult voices.
//
import SwiftUI

struct TypecastCharacterPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var typecast = TypecastClient.shared

    @State private var searchQuery = ""
    @State private var selectedCategory = "전체"

    private let categories = ["전체", "대화/일상", "아나운서/기자", "오디오북/낭독", "라디오/팟캐스트", "광고/홍보"]

    private var filteredCharacters: [TypecastCharacter] {
        TypecastCatalog.search(query: searchQuery, category: selectedCategory)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category Pills
                categoryPills
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
        }
    }

    // MARK: - Category Filter Pills

    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    let isSelected = selectedCategory == cat
                    let count = cat == "전체" ? TypecastCatalog.characters.count : TypecastCatalog.search(query: "", category: cat).count
                    Button {
                        selectedCategory = cat
                    } label: {
                        HStack(spacing: 4) {
                            Text(cat)
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

    // MARK: - Character Row

    private func characterRow(_ char: TypecastCharacter) -> some View {
        let isSelected = typecast.selectedVoiceId == char.nameKo ||
                         typecast.selectedVoiceId == char.id ||
                         typecast.selectedVoiceId == char.nameEn

        return HStack(spacing: 12) {
            // Face Portrait Thumbnail
            TypecastVoiceThumbnail(voice: char.nameKo, size: 44)

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
                    .lineLimit(1)
            }

            Spacer()

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
        .contentShape(Rectangle())
        .onTapGesture {
            selectCharacter(char)
        }
    }

    private func selectCharacter(_ char: TypecastCharacter) {
        typecast.selectedVoiceId = char.nameKo
        UserDefaults.standard.set("typecast:\(char.nameKo)", forKey: "voiceIdentifier")
        model.voice.say("\(char.nameKo) 음성을 선택했습니다.", category: "voiceControl", manual: true)
        dismiss()
    }
}
