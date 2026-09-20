import SwiftUI

/// v31: long "this is an estimate / not a diagnosis" captions moved off the screen into an ⓘ popover,
/// so a card shows the value and nothing else. Safety-critical warnings stay inline.
struct InfoNote: View {
    let title: String
    let text: String
    @State private var shown = false

    init(_ title: String = "설명", _ text: String) {
        self.title = title
        self.text = text
    }

    var body: some View {
        Button { shown = true } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 16))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.muted)
        .accessibilityLabel(title + " 설명 보기")
        .popover(isPresented: $shown) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title).font(.headline)
                    Text(text).font(.subheadline).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 280, idealWidth: 320, maxHeight: 360)
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// Card header: icon, title, optional ⓘ. Keeps every card in the app on the same rhythm.
struct CardTitle: View {
    let title: String
    var systemImage: String? = nil
    var info: String? = nil
    var infoTitle: String? = nil
    var body: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 17)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            }
            Text(title).font(.headline)
            Spacer(minLength: 4)
            if let info { InfoNote(infoTitle ?? title, info) }
        }
    }
}
