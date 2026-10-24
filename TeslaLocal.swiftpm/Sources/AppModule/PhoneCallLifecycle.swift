import CallKit
import Foundation

/// CallKit reports call completion even when the app remains behind the Phone UI.
/// No phone numbers or other call details are read or retained.
final class PhoneCallLifecycle: NSObject, CXCallObserverDelegate {
    private let observer = CXCallObserver()
    private var active = false
    var changed: ((Bool) -> Void)?
    override init() {
        super.init()
        observer.setDelegate(self, queue: .main)
        active = observer.calls.contains { !$0.hasEnded }
    }
    var isActive: Bool { active }
    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        let next = callObserver.calls.contains { !$0.hasEnded }
        guard next != active else { return }
        active = next; changed?(next)
    }
}
