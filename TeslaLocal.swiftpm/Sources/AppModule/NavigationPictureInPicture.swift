import SwiftUI
import UIKit
import AVKit
import AVFoundation
import CoreMedia
import CoreVideo

private final class NavigationPipPlaybackState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var paused: Bool {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); defer { lock.unlock() }; value = newValue }
    }
}

@MainActor final class NavigationPictureInPicture: NSObject, ObservableObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    static let shared = NavigationPictureInPicture()
    let layer = AVSampleBufferDisplayLayer()
    private var controller: AVPictureInPictureController?
    private weak var source: UIView?
    private var state: VehicleActivityAttributes.ContentState?
    private var enabled = false, suppressed = false, returning = false
    private var requestedAutomatically = true
    private nonisolated let playback = NavigationPipPlaybackState()
    private var paused: Bool { get { playback.paused } set { playback.paused = newValue } }
    private var timer: Timer?
    private var preparation: Task<Void, Never>?
    private var displayCheck: Task<Void, Never>?
    private var pool: CVPixelBufferPool?
    private var lastFrameAt = Date.distantPast
    private var observers: [NSObjectProtocol] = []
    private var possibleObservation: NSKeyValueObservation?
    @Published private(set) var status = "길안내 중에만 표시"
    @Published private(set) var active = false
    @Published private(set) var renderedFrames = 0
    private var lastError = ""
    private var surfaceBacked = false
    private var frameReady: Bool {
        if #available(iOS 17.4, *) { return layer.isReadyForDisplay }
        return layer.status == .rendering
    }
    var supported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }
    var diagnostics: String {
        "지원 \(supported) · 준비 \(controller?.isPictureInPicturePossible == true) · 영상 \(layer.status.rawValue) · 표시 \(frameReady) · 공유 \(surfaceBacked) · \(lastError)"
    }
    override init() {
        super.init()
        layer.videoGravity = .resizeAspect
        var timebase: CMTimebase?
        if CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase) == noErr, let timebase {
            CMTimebaseSetTime(timebase, time: CMClockGetTime(CMClockGetHostTimeClock())); CMTimebaseSetRate(timebase, rate: 1)
            layer.controlTimebase = timebase
        }
        let attributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 720, kCVPixelBufferHeightKey as String: 420,
            kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, [kCVPixelBufferPoolMinimumBufferCountKey as String: 2] as CFDictionary, attributes as CFDictionary, &pool)
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if note.name == UIApplication.didEnterBackgroundNotification { self.start(automatic: true) }
                    else if self.active { self.returning = true; self.controller?.stopPictureInPicture() }
                }
            })
        }
    }
    deinit { timer?.invalidate(); observers.forEach(NotificationCenter.default.removeObserver) }
    func attach(_ view: UIView) {
        if source === view, layer.superlayer === view.layer, layer.frame == view.bounds { return }
        source = view
        if layer.superlayer !== view.layer { layer.removeFromSuperlayer(); view.layer.addSublayer(layer) }
        layer.frame = view.bounds
        if controller == nil, supported {
            let content = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer, playbackDelegate: self)
            controller = AVPictureInPictureController(contentSource: content)
            controller?.delegate = self; controller?.requiresLinearPlayback = true
            possibleObservation = controller?.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.refreshReadiness() }
            }
        }
        refreshReadiness(); render()
    }
    func update(_ state: VehicleActivityAttributes.ContentState, enabled: Bool) {
        let wasGuiding = self.state?.guiding == true
        self.state = state; self.enabled = enabled
        if !state.guiding { suppressed = false; paused = false; stop(); return }
        if !wasGuiding { suppressed = false; paused = false; lastError = "" }
        guard enabled else { stop(); return }
        guard !suppressed else { status = lastError.isEmpty ? "플로팅 안내 닫힘 · 앱에서 다시 시작 가능" : "플로팅 영상 표시 실패 · 잠금화면 안내 사용"; return }
        refreshReadiness()
        render()
    }
    private func refreshReadiness() {
        guard enabled, state?.guiding == true, !suppressed else { return }
        guard supported else { status = "이 기기에서 플로팅 안내 지원 안 됨"; return }
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
        if source?.window != nil { try? VoiceAudioRouting.activateFloatingGuidance() }
        if !active { status = controller?.isPictureInPicturePossible == true ? "앱 전환 시 플로팅 안내 대기" : "플로팅 화면 준비 중" }
    }
    func start(automatic: Bool = false) {
        guard enabled else { status = "플로팅 안내 꺼짐"; return }
        guard state?.guiding == true else { status = "길안내 중에만 표시"; return }
        requestedAutomatically = automatic
        if !automatic { suppressed = false; lastError = ""; refreshReadiness(); render() }
        guard !suppressed, supported, let controller, !controller.isPictureInPictureActive else { return }
        guard controller.isPictureInPicturePossible else {
            guard preparation == nil else { return }
            status = "플로팅 화면 준비 중"
            preparation = Task { @MainActor [weak self] in
                for _ in 0..<4 {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled, let self, self.enabled, self.state?.guiding == true, !self.suppressed else { return }
                    self.render()
                    if self.controller?.isPictureInPicturePossible == true {
                        self.preparation = nil; self.start(automatic: automatic); return
                    }
                }
                self?.preparation = nil; self?.status = "플로팅 화면 준비 지연 · 앱에서 다시 시도"
            }
            return
        }
        do { try VoiceAudioRouting.activateFloatingGuidance(force: true); render(force: true); controller.startPictureInPicture() }
        catch { status = "플로팅 안내 시작 실패"; VoiceAudioRouting.release(owner: "navigation.pip") }
    }
    private func stop() {
        displayCheck?.cancel(); displayCheck = nil
        preparation?.cancel(); preparation = nil
        controller?.canStartPictureInPictureAutomaticallyFromInline = false
        timer?.invalidate(); timer = nil
        if controller?.isPictureInPictureActive == true { returning = true; controller?.stopPictureInPicture() }
        layer.flushAndRemoveImage(); lastFrameAt = .distantPast; VoiceAudioRouting.release(owner: "navigation.pip")
        status = enabled ? "길안내 중에만 표시" : "플로팅 안내 꺼짐"
    }
    private func render(force: Bool = false) {
        guard enabled, !suppressed, let state, state.guiding, let pool else { return }
        guard force || Date().timeIntervalSince(lastFrameAt) >= 1 else { return }
        if layer.status == .failed { layer.flush() }
        guard layer.isReadyForMoreMediaData else { return }
        var pixel: CVPixelBuffer?
        let limit = [kCVPixelBufferPoolAllocationThresholdKey as String: 3] as CFDictionary
        let allocation = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, limit, &pixel)
        if allocation == kCVReturnWouldExceedAllocationThreshold { return }
        guard allocation == kCVReturnSuccess, let pixel else { lastError = "영상 버퍼 \(allocation)"; return }
        surfaceBacked = CVPixelBufferGetIOSurface(pixel) != nil
        guard surfaceBacked else { lastError = "공유 영상 버퍼 생성 실패"; return }
        CVPixelBufferLockBaseAddress(pixel, [])
        let bitmap = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: 720, height: 420, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmap),
              let image = NavigationPipFrame.image(state, stale: NavigationCardFormat.stale(observedAt: state.observedAt), paused: paused).cgImage else {
            CVPixelBufferUnlockBaseAddress(pixel, []); return
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 720, height: 420))
        CVPixelBufferUnlockBaseAddress(pixel, [])
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel, formatDescriptionOut: &format) == noErr, let format else { return }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 1), presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample else { return }
        layer.enqueue(sample); lastFrameAt = Date(); renderedFrames += 1; lastError = ""
    }
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        render(force: true)
        timer?.invalidate()
        let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor [weak self] in self?.render() } }
        tick.tolerance = 0.25; timer = tick; RunLoop.main.add(tick, forMode: .common)
    }
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        active = true
        render(force: true)
        if requestedAutomatically, UIApplication.shared.applicationState == .active {
            returning = true; pictureInPictureController.stopPictureInPicture(); return
        }
        status = "플로팅 안내 표시 중"
        print("NAV_PIP_DID_START")
        displayCheck?.cancel()
        displayCheck = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self, self.active else { return }
            if !self.frameReady || self.layer.status == .failed {
                self.lastError = self.layer.error.map { ($0 as NSError).domain + " \(($0 as NSError).code)" } ?? "영상 표시 준비 실패"
                self.returning = true; self.suppressed = true
                self.controller?.stopPictureInPicture()
                self.status = "플로팅 영상 표시 실패 · 잠금화면 안내 사용"
                print("NAV_PIP_DISPLAY_FAILED \(self.diagnostics)")
            }
        }
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        displayCheck?.cancel(); displayCheck = nil
        let detail = error as NSError; lastError = "\(detail.domain) \(detail.code)"
        print("NAV_PIP_START_FAILED \(lastError)")
        preparation?.cancel(); preparation = nil
        active = false; timer?.invalidate(); timer = nil; VoiceAudioRouting.release(owner: "navigation.pip"); status = "플로팅 안내 시작 실패 · 기기 설정 확인"
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        displayCheck?.cancel(); displayCheck = nil
        preparation?.cancel(); preparation = nil; requestedAutomatically = true
        active = false; timer?.invalidate(); timer = nil
        if !returning { suppressed = true }
        returning = false; controller?.canStartPictureInPictureAutomaticallyFromInline = !suppressed && enabled && state?.guiding == true
        VoiceAudioRouting.release(owner: "navigation.pip")
        status = !enabled ? "플로팅 안내 꺼짐" : state?.guiding != true ? "길안내 종료됨" : suppressed && !lastError.isEmpty ? "플로팅 영상 표시 실패 · 잠금화면 안내 사용" : "플로팅 안내 닫힘 · 앱에서 다시 시작 가능"
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        returning = true
        guard let url = URL(string: "ylcompanion://activity") else { completionHandler(false); return }
        UIApplication.shared.open(url, options: [:], completionHandler: completionHandler)
    }
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        playback.paused = !playing
        Task { @MainActor [weak self] in self?.render(); pictureInPictureController.invalidatePlaybackState() }
    }
    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange { CMTimeRange(start: .zero, duration: .positiveInfinity) }
    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool { playback.paused }
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) { Task { @MainActor [weak self] in self?.render() } }
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping @Sendable () -> Void) { completionHandler() }
}

struct NavigationPipSource: UIViewRepresentable {
    let manager: NavigationPictureInPicture
    func makeUIView(context: Context) -> NavigationPipSurface { let view = NavigationPipSurface(); view.manager = manager; return view }
    func updateUIView(_ view: NavigationPipSurface, context: Context) { manager.attach(view) }
}
final class NavigationPipSurface: UIView {
    weak var manager: NavigationPictureInPicture?
    override func layoutSubviews() { super.layoutSubviews(); manager?.attach(self) }
    override func didMoveToWindow() { super.didMoveToWindow(); manager?.attach(self) }
}
