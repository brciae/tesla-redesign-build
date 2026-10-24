import SwiftUI
import CoreMotion

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
    static func apply(_ requested: UIInterfaceOrientationMask, scene targetScene: UIWindowScene?) {
        let value = requested == .all ? (DeviceTiltOrientation.locked ?? requested) : requested
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
/// v1.24: 자동 mode follows the phone's physical tilt even when iOS rotation lock is on.
/// The accelerometer decides portrait/landscape and the scene is asked for exactly that orientation.
enum DeviceTiltOrientation {
    private static let motion = CMMotionManager()
    private static var current: UIInterfaceOrientationMask?
    static var locked: UIInterfaceOrientationMask? { motion.isAccelerometerActive ? current : nil }
    private static weak var scene: UIWindowScene?
    static func follow(_ on: Bool, scene target: UIWindowScene?) {
        guard on, let target, motion.isAccelerometerAvailable else {
            if motion.isAccelerometerActive { motion.stopAccelerometerUpdates() }
            current = nil
            return
        }
        scene = target
        guard !motion.isAccelerometerActive else { return }
        motion.accelerometerUpdateInterval = 0.25
        motion.startAccelerometerUpdates(to: .main) { data, _ in
            guard let a = data?.acceleration else { return }
            let x = a.x, y = a.y
            guard abs(a.z) < 0.85 else { return }               // lying flat: keep the last orientation
            var next: UIInterfaceOrientationMask?
            if abs(x) > abs(y) + 0.25 { next = x < 0 ? .landscapeRight : .landscapeLeft }
            else if abs(y) > abs(x) + 0.25, y < 0 { next = .portrait }
            guard let next, next != current, let scene else { return }
            current = next
            NavigationOrientation.apply(next, scene: scene)
        }
    }
}
final class YLApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = ChargeNotificationManager.shared
        return true
    }
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        if let scene = NavigationOrientation.scene, window?.windowScene === scene { return NavigationOrientation.mask }
        return .all
    }
}
