import SwiftUI

/// InfoNote renders EmptyView to keep all cards clean and free from developer disclaimers.
struct InfoNote: View {
    let title: String
    let text: String

    init(_ title: String = "설명", _ text: String) {
        self.title = title
        self.text = text
    }

    @State private var open = false
    var body: some View {
        // v1.55: ⓘ icon that opens the full note (was hidden entirely)
        Button { open = true } label: { Image(systemName: "info.circle").font(.footnote).foregroundStyle(.secondary) }
            .buttonStyle(.plain)
            .accessibilityLabel(title + " 설명")
            .popover(isPresented: $open) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
                }.padding(16).frame(maxWidth: 320).presentationCompactAdaptation(.popover)
            }
    }
}

/// Card header: icon and title in clean modern iOS design.
struct CardTitle: View {
    let title: String
    var systemImage: String? = nil
    var info: String? = nil
    var infoTitle: String? = nil
    var body: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer(minLength: 4)
        }
    }
}

/// Charts draw in with a left-to-right wipe and a soft fade the first time they appear.
struct ChartReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    func body(content: Content) -> some View {
        content
            // The wipe only masks horizontally: 40 pt of slack above and below keeps
            // top annotations, a 100 % line's stroke and axis labels from being clipped.
            .mask(alignment: .leading) {
                GeometryReader { g in
                    Rectangle().frame(width: progress >= 1 ? g.size.width + 80 : g.size.width * progress, height: g.size.height + 80)
                        .offset(x: progress >= 1 ? -40 : 0, y: -40)
                }
            }
            .opacity(0.35 + 0.65 * Double(progress))
            .onAppear {
                guard progress < 1 else { return }
                if reduceMotion { progress = 1 } else { withAnimation(.smooth(duration: 1.1).delay(0.08)) { progress = 1 } }
            }
    }
}
extension View { func chartReveal() -> some View { modifier(ChartReveal()) } }

/// Light/dark helpers live here (not in App.swift) so the interface probe, which has its own Theme, compiles too.
extension Theme {
    /// Card fill: the old `Color(white:)` value in dark mode, plain white in light mode.
    static func fill(_ white: CGFloat) -> Color { adaptive(dark: UIColor(white: white, alpha: 1), light: UIColor.white) }
    static func adaptive(dark: UIColor, light: UIColor) -> Color { Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light }) }
}

/// iOS 18 zoom navigation (card grows into its detail screen); plain push on iOS 17.
extension View {
    @ViewBuilder func zoomSource(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) { self.matchedTransitionSource(id: id, in: namespace) } else { self }
    }
    @ViewBuilder func zoomDestination(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) { self.navigationTransition(.zoom(sourceID: id, in: namespace)) } else { self }
    }
    /// Cards settle in as they scroll into view: slight scale, fade and blur at the edges.
    func cardScrollEffect() -> some View {
        scrollTransition(.interactive, axis: .vertical) { content, phase in
            content.opacity(phase.isIdentity ? 1 : 0.55)
                .scaleEffect(phase.isIdentity ? 1 : 0.95)
                .blur(radius: phase.isIdentity ? 0 : 1.5)
        }
    }
}
