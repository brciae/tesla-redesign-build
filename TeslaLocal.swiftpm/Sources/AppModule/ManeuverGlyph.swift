import SwiftUI

/// Clock direction, not an invented exit ordinal. No inferred lane guidance.
struct ManeuverGlyph: View {
    let symbol: String
    var exitClock: Int = 0
    let size: CGFloat
    private var rotary: Bool { (1...12).contains(exitClock) }
    private var branch: Bool { symbol == "arrow.up.right" || symbol == "arrow.up.left" }
    var body: some View {
        Group {
            if rotary || branch {
                Canvas { context, _ in
                    context.scaleBy(x: size / 100, y: size / 100)
                    let stroke = StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
                    func point(_ angle: Double, _ radius: Double = 27) -> CGPoint {
                        let a = angle * .pi / 180
                        return CGPoint(x: 50 + radius * sin(a), y: 50 - radius * cos(a))
                    }
                    func arrow(_ tip: CGPoint, _ angle: Double) -> Path {
                        let a = angle * .pi / 180, dx = sin(a), dy = -cos(a)
                        var p = Path()
                        p.move(to: CGPoint(x: tip.x - dx * 12 - dy * 9, y: tip.y - dy * 12 + dx * 9))
                        p.addLine(to: tip)
                        p.addLine(to: CGPoint(x: tip.x - dx * 12 + dy * 9, y: tip.y - dy * 12 - dx * 9))
                        return p
                    }
                    var route = Path()
                    if rotary {
                        let target = Double(exitClock % 12) * 30
                        let sweep = (160 - target + 360).truncatingRemainder(dividingBy: 360)
                        let start = point(160)
                        route.move(to: CGPoint(x: start.x, y: 94)); route.addLine(to: start)
                        // Sample the arc explicitly: UIKit's flipped Y and full-circle special cases cannot reverse it.
                        for step in 1...90 { route.addLine(to: point(160 - sweep * Double(step) / 90)) }
                        let tip = point(target, 44)
                        route.addLine(to: tip)
                        context.stroke(route, with: .color(.white), style: stroke)
                        context.stroke(arrow(tip, target), with: .color(.white), style: stroke)
                    } else {
                        var straight = Path()
                        straight.move(to: CGPoint(x: 50, y: 90)); straight.addLine(to: CGPoint(x: 50, y: 10))
                        context.stroke(straight, with: .color(.white.opacity(0.4)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        let right = symbol == "arrow.up.right"
                        let tip = CGPoint(x: right ? 82 : 18, y: 18)
                        route.move(to: CGPoint(x: 50, y: 90)); route.addLine(to: CGPoint(x: 50, y: 58)); route.addLine(to: tip)
                        context.stroke(route, with: .color(.white), style: stroke)
                        context.stroke(arrow(tip, right ? 39 : -39), with: .color(.white), style: stroke)
                    }
                }
            } else {
                Image(systemName: symbol).resizable().scaledToFit().foregroundStyle(.white).padding(size * 0.08)
            }
        }.frame(width: size, height: size)
            .accessibilityLabel(rotary ? "회전교차로 \(exitClock)시 방향 출구" : "진행 방향")
    }
}
