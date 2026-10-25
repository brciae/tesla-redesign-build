import UIKit

/// The exact image supplied to the public sample-buffer PiP layer. No traffic colours are inferred.
enum NavigationPipFrame {
    static let size = CGSize(width: 360, height: 210)
    private static let arrival: DateFormatter = { let f = DateFormatter(); f.timeStyle = .short; return f }()
    @MainActor static func image(_ state: VehicleActivityAttributes.ContentState, stale: Bool, paused: Bool = false) -> UIImage {
        let unavailable = stale || paused
        let format = UIGraphicsImageRendererFormat(); format.scale = 2; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let cg = renderer.cgContext
            UIColor.white.setFill(); cg.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.02, green: 0.35, blue: 0.96, alpha: 1).setFill(); cg.fill(CGRect(x: 0, y: 0, width: 360, height: 132))
            func text(_ value: String, _ rect: CGRect, _ font: CGFloat, _ color: UIColor = .white, bold: Bool = true, centered: Bool = false) {
                let p = NSMutableParagraphStyle(); p.lineBreakMode = .byWordWrapping; p.alignment = centered ? .center : .left
                (value as NSString).draw(in: rect, withAttributes: [.font: UIFont.systemFont(ofSize: font, weight: bold ? .bold : .medium), .foregroundColor: color, .paragraphStyle: p])
            }
            func symbol(_ name: String, _ rect: CGRect, color: UIColor = .white) {
                UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: rect.height, weight: .bold))?
                    .withTintColor(color, renderingMode: .alwaysOriginal).draw(in: rect)
            }
            symbol(unavailable ? "location.slash" : state.turnSymbol ?? "location.fill", CGRect(x: 18, y: 23, width: 42, height: 42))
            text(paused ? "화면 일시정지" : stale ? "업데이트 대기" : state.turnMetres.map(NavigationCardFormat.distance) ?? "길안내", CGRect(x: 76, y: 13, width: 220, height: 40), unavailable ? 23 : 32)
            text(paused ? "길안내는 계속 진행" : stale ? "위치 수신 확인" : GuidanceCardText.label(state.instruction, symbol: state.turnSymbol ?? "", exitClock: state.exitClock ?? 0), CGRect(x: 76, y: 56, width: 214, height: 43), 16)
            if !unavailable, let limit = state.speedLimit {
                let circle = UIBezierPath(ovalIn: CGRect(x: 307, y: 13, width: 40, height: 40))
                UIColor.white.setFill(); circle.fill(); UIColor.systemRed.setStroke(); circle.lineWidth = 3; circle.stroke()
                text("\(limit)", CGRect(x: 308, y: 20, width: 38, height: 28), 22, .black, centered: true)
                if let metres = state.speedLimitMetres { text(NavigationCardFormat.distance(metres), CGRect(x: 296, y: 58, width: 62, height: 20), 11, centered: true) }
            }
            if !unavailable, let progress = state.routeProgress, progress.isFinite, (0...1).contains(progress) {
                UIColor.white.withAlphaComponent(0.3).setFill(); cg.fill(CGRect(x: 18, y: 96, width: 324, height: 3))
                UIColor.white.setFill(); cg.fill(CGRect(x: 18, y: 96, width: 324 * progress, height: 3))
            }
            UIColor.black.withAlphaComponent(0.1).setFill(); cg.fill(CGRect(x: 0, y: 105, width: 360, height: 27))
            if !unavailable, let metres = state.nextTurnMetres, let next = state.nextTurnSymbol, !next.isEmpty {
                symbol(next, CGRect(x: 20, y: 109, width: 19, height: 19))
                text(NavigationCardFormat.distance(metres), CGRect(x: 48, y: 109, width: 100, height: 22), 16)
            }
            if !unavailable, let count = state.laneCount, (1...8).contains(count), let suggested = state.laneSuggested, !suggested.isEmpty {
                let laneWidth: CGFloat = 24, start = (360 - CGFloat(count) * laneWidth) / 2
                for lane in 0..<count {
                    let bar = UIBezierPath(roundedRect: CGRect(x: start + CGFloat(lane) * laneWidth + 7, y: 139, width: 6, height: 22), cornerRadius: 3)
                    (suggested.contains(lane) ? UIColor.systemBlue : UIColor.lightGray).setFill(); bar.fill()
                }
                text("권장 차로", CGRect(x: 145, y: 164, width: 70, height: 15), 10, .darkGray, bold: false, centered: true)
            }
            if unavailable { text(paused ? "화면 재생 버튼으로 복귀" : "앱에서 수신 상태 확인", CGRect(x: 18, y: 166, width: 324, height: 24), 15, .darkGray, centered: true) }
            else {
                if let at = state.arrivalAt { text(arrival.string(from: at) + " 도착", CGRect(x: 14, y: 184, width: 135, height: 24), 13, .black) }
                if let minutes = state.remainingMinutes { text("\(minutes)분", CGRect(x: 146, y: 184, width: 68, height: 24), 13, .black, centered: true) }
                if let metres = state.remainingMetres { text(NavigationCardFormat.distance(metres), CGRect(x: 235, y: 184, width: 111, height: 24), 13, .black, centered: true) }
            }
        }
    }
}
