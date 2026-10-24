import Foundation
import SwiftUI

/// Display-only compression. Spoken guidance and recorded source instructions remain intact.
enum GuidanceCardText {
    static func action(_ text: String, symbol: String, exitClock: Int) -> String {
        if symbol.contains("circlepath"), (1...12).contains(exitClock) { return "\(exitClock)시 방향 출구" }
        let actions = ["비보호 좌회전", "오른쪽 진출", "왼쪽 진출", "오른쪽 출구", "왼쪽 출구",
                       "오른쪽 진입", "왼쪽 진입", "오른쪽 분기", "왼쪽 분기", "오른쪽 방향", "왼쪽 방향",
                       "분기 후 합류", "좌회전", "우회전", "유턴", "회전교차로", "요금소", "경유지", "도착", "직진", "진출", "진입", "출구", "진행"]
        if let action = actions.first(where: { text.hasSuffix($0) }) { return action }
        return text.count <= 22 ? text : "진행 방향 확인"
    }
    static func label(_ text: String, symbol: String, exitClock: Int) -> String {
        let clean = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let action = action(clean, symbol: symbol, exitClock: exitClock)
        if symbol.contains("circlepath"), (1...12).contains(exitClock) { return action }
        if clean.count <= 22 { return clean }
        guard clean.hasSuffix(action) else { return action }
        // Keep one complete sign/place name; never cut a road name into an ellipsis.
        let places = String(clean.dropLast(action.count)).trimmingCharacters(in: .whitespaces)
        let first = places.components(separatedBy: " · ").first ?? ""
        let candidate = first + " " + action
        return candidate.count <= 22 ? candidate : action
    }
}

struct GuidanceCardLabel: View {
    let text: String
    var symbol = ""
    var exitClock = 0
    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(GuidanceCardText.label(text, symbol: symbol, exitClock: exitClock))
                .lineLimit(1).fixedSize(horizontal: true, vertical: true)
            Text(GuidanceCardText.action(text, symbol: symbol, exitClock: exitClock))
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
    }
}
