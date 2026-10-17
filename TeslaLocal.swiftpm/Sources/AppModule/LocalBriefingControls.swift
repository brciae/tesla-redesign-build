import SwiftUI

/// Sheet/editor summaries must read their local draft or filtered rows, never global vehicle data.
struct LocalBriefingControls: View {
    let title: String
    let summary: () -> [String]
    var body: some View {
        EmptyView()
    }
}
