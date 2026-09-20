import SwiftUI

enum NavigationDirection: String, CaseIterable, Identifiable {
    case auto, portrait, landscape
    var id: String { rawValue }
    var title: String { switch self { case .portrait: return "세로"; case .landscape: return "가로"; case .auto: return "자동" } }
    var mask: UIInterfaceOrientationMask { switch self { case .portrait: return .portrait; case .landscape: return .landscape; case .auto: return .all } }
}
enum NavigationOrientation {
    static var mask: UIInterfaceOrientationMask = .all
    static var failure: ((String) -> Void)?
    static weak var scene: UIWindowScene?
    static func apply(_ value: UIInterfaceOrientationMask, scene targetScene: UIWindowScene?) {
        mask = value
        scene = targetScene
        guard let scene = targetScene, scene.activationState == .foregroundActive,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
        root.setNeedsUpdateOfSupportedInterfaceOrientations()
        var top = root
        while let next = top.presentedViewController { top = next }
        top.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: value)) { _ in
            DispatchQueue.main.async { failure?("방향 설정 저장됨 · 시스템 회전 잠금·iPad 전체 화면 상태 확인 필요") }
        }
    }
}
final class YLApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        if let scene = NavigationOrientation.scene, window?.windowScene === scene { return NavigationOrientation.mask }
        return .all
    }
}
