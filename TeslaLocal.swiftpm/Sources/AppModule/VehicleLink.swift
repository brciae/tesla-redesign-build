import Foundation
import CoreBluetooth
import Combine
import UIKit
import CryptoKit

struct ControlConfirmation: Identifiable {
    let id: String
    let action: String
    let title: String
    let args: Object
    let warning: String
}

final class VehicleLink: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var status = "차량 연결 전"
    @Published var connected = false
    @Published var authentic = false
    @Published var telemetryGroups: Object = [:]
    @Published var busy = false
    @Published var closuresSupported = true
    @Published var sessionStartedAt: Double = 0
    @Published var ignoredReplies = 0
    @Published var responseTimeouts = 0
    @Published var recoveryAttempts = 0
    @Published var deferredGroups: Set<String> = []
    @Published var timedOutGroups: Set<String> = []
    @Published var refreshing = false
    @Published var refreshedGroups: Set<String> = []
    @Published var controlEnabled = false
    @Published var controlBusy = false
    @Published var controlStatus = "제어 키 준비 전"
    var onControlOutcome: ((String) -> Void)?
    @Published var confirmation: ControlConfirmation?
    @Published var preparingControl = false
    @Published var diagnostics = [String]()
    /// v30 car media controls (no P interlock, no confirmation, never retried).
    @Published private(set) var mediaStatus = ""
    @Published private(set) var mediaInFlight = false
    private var controlPreferenceKey = ""
    private var pendingControl: (action: String, title: String, args: Object, until: TimeInterval)?
    private var preparationTimer: Timer?
    private var preparationNeedsDrive = false
    private var automationAuthorization: (() -> Bool)?
    private var automationCompletion: ((String) -> Void)?
    private var automationGate: AutomationWriteGate?
    private var controlAuthRequested = false
    private var controlAuthFailures = [String]()
    private var controlAuthRetryAt: TimeInterval = 0
    private var groupRetryAt: [String: TimeInterval] = [:]
    private var protocolResyncs = 0
    private var foreground = false
    private var backgroundRead = false
    /// v29: user allowed background reads; survives a transport reset so a background disconnect can reconnect.
    private var backgroundWanted = false
    private var readAllowed: Bool { foreground || backgroundRead }
    var supportsBackgroundRead: Bool { (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []).contains("bluetooth-central") }
    private var wantedVIN = ""
    private var userDisconnected = false
    private var retryTimer: Timer?
    private var retryCount = 0
    private var burst = [String]()
    private var controlDomain: Int?
    private var commandInFlight = false
    private var controlSpeechIntent: ControlConfirmation?
    @Published private(set) var commandUncertain = false
    private var verifiedControlDomains: Set<Int> = []
    private var preparingDomains = [Int]()
    private let refreshGroups = VehicleReadPlan.initial
    private var lastReadGear: String?
    var onSnapshot: ((Object) -> Void)?
    var onReadAvailabilityChange: (() -> Void)?
    private let runtime: LocalRuntime
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writer: CBCharacteristic?
    private var reader: CBCharacteristic?
    private var expectedName = ""
    private var scanRequested = false
    private var chunks = [Data]()
    private var writeInFlight = false
    private var awaitingReply = false
    private var pairing = false
    private var pollTimer: Timer?
    private var deadline: Timer?
    private var queryIndex = 0
    private var consecutiveTimeouts = 0
    private var currentReadGroup = ""
    private let service = CBUUID(string: "00000211-b2d1-43f0-9b88-960cebf8b91e")
    private let writeID = CBUUID(string: "00000212-b2d1-43f0-9b88-960cebf8b91e")
    private let readID = CBUUID(string: "00000213-b2d1-43f0-9b88-960cebf8b91e")
    init(runtime: LocalRuntime) {
        self.runtime = runtime; super.init()
        commandUncertain = UserDefaults.standard.bool(forKey: "manualControlPending") || UserDefaults.standard.bool(forKey: "manualControlUncertain")
        if commandUncertain { UserDefaults.standard.set(true, forKey: "manualControlUncertain") }
        if commandUncertain { controlStatus = "이전 실행의 제어 결과 미확인 · 차량을 직접 확인해야 함" }
    }
    func enableControls(_ enabled: Bool) {
        guard !commandInFlight else { return }
        guard !controlPreferenceKey.isEmpty else { return }
        controlEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: controlPreferenceKey)
        _ = try? runtime.call("controlContext", ["foreground": foreground, "enabled": controlEnabled])
        if !controlEnabled { cancelConfirmation() }
        controlAuthRequested = enabled
        controlAuthRetryAt = 0
        controlStatus = controlEnabled ? "수동 제어 설정 저장됨 · 연결 후 인증 자동 준비" : "제어 사용 꺼짐 · 설정 저장됨"
        poll()
    }
    private func selectVehicle(_ vin: String) {
        wantedVIN = vin
        let digest = SHA256.hash(data: Data(vin.utf8)).map { String(format: "%02x", $0) }.joined()
        controlPreferenceKey = vin.isEmpty ? "" : "manualControlEnabled." + digest
        // The user requested one-tap controls. Vehicle enrollment remains explicit;
        // this preference never enrolls or changes the permissions of a key.
        controlEnabled = !vin.isEmpty && (UserDefaults.standard.object(forKey: controlPreferenceKey) == nil || UserDefaults.standard.bool(forKey: controlPreferenceKey))
    }
    private func trace(_ event: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        diagnostics.append("\(stamp) · \(event.prefix(240))")
        if diagnostics.count > 80 { diagnostics.removeFirst(diagnostics.count - 80) }
    }
    private func completeAutomation(_ message: String) {
        let callback = automationCompletion
        automationAuthorization = nil; automationCompletion = nil; automationGate = nil
        callback?(message)
    }
    func cancelPendingAutomation() {
        guard automationAuthorization != nil, !commandInFlight else { return }
        cancelConfirmation()
    }
    func cancelConfirmation() {
        preparationTimer?.invalidate(); preparationTimer = nil; confirmation = nil; pendingControl = nil
        preparingControl = false; preparationNeedsDrive = false; _ = try? runtime.call("controlCancel")
        if !commandInFlight { completeAutomation("조건 변경·취소 · 명령 전송 없음") }
    }
    func acknowledgeUnknownResult() {
        guard !commandInFlight, !controlBusy, confirmation == nil else { return }
        commandUncertain = false
        UserDefaults.standard.set(false, forKey: "manualControlUncertain")
        UserDefaults.standard.set(false, forKey: "manualControlPending")
        controlStatus = "직전 미확인 명령의 실제 상태를 직접 확인한 것으로 기록함"
    }
    private func invalidateControls(interrupted: Bool) {
        if interrupted { commandUncertain = true; UserDefaults.standard.set(true, forKey: "manualControlUncertain"); controlStatus = "직전 제어 결과 미확인 · 실제 차량 상태 확인 필요 · 자동 재전송 안함" }
        if commandInFlight { completeAutomation("연결·앱 상태 변경 · 제어 결과 미확인 · 재전송 안함") }
        controlSpeechIntent = nil
        cancelConfirmation(); controlDomain = nil; commandInFlight = false; controlBusy = false
        verifiedControlDomains = []; preparingDomains = []; controlAuthRequested = controlEnabled
    }
    func enrollControlKey() {
        guard foreground, connected, !awaitingReply, !writeInFlight, chunks.isEmpty, !controlBusy, confirmation == nil else { controlStatus = "조회 응답 완료 후 등록 요청을 다시 눌러야 함"; return }
        pairing = true; authentic = false; pollTimer?.invalidate(); invalidateControls(interrupted: false)
        _ = try? runtime.call("wireAbandon")
        onReadAvailabilityChange?()
        do {
            let packet = try runtime.call("wireControlEnroll") as? String ?? ""
            try send(packet)
            controlStatus = "별도 Driver 제어 키 등록 요청 전송됨 · 차량에서 키카드·화면 승인 후 조회 연결부터 재개"
            status = "차량 키카드 승인 대기 · 기존 조회 키는 유지됨"
        } catch { fail(error.localizedDescription) }
    }
    func prepareControlKeys() {
        guard foreground, authentic, controlEnabled, !commandInFlight, confirmation == nil else { controlStatus = "조회 연결·제어 사용 확인 필요"; return }
        controlAuthRequested = true; controlAuthRetryAt = 0
        controlStatus = "현재 조회 완료 후 제어 인증 자동 준비"; poll()
    }
    private func startControlAuthentication() {
        guard foreground, authentic, controlEnabled, !awaitingReply, !writeInFlight, chunks.isEmpty, !controlBusy, confirmation == nil else { return }
        controlAuthRequested = false
        controlAuthFailures = []
        controlBusy = true; preparingDomains = [2, 3].filter { !verifiedControlDomains.contains($0) }
        trace("제어 인증 시작 · 명령 전송 없음")
        controlStatus = "제어 키 인증 중 · 차량 동작 명령 없음"; continueControlAuthentication()
    }
    private func continueControlAuthentication() {
        guard controlBusy, !commandInFlight, !awaitingReply, !writeInFlight, chunks.isEmpty else { return }
        guard !preparingDomains.isEmpty else {
            controlBusy = false; controlDomain = nil
            controlAuthRetryAt = ProcessInfo.processInfo.systemUptime + (controlAuthFailures.isEmpty ? 240 : 60)
            controlStatus = controlAuthFailures.isEmpty ? "제어 준비됨 · 기능 버튼을 누르면 1회 실행" : controlAuthFailures.joined(separator: " · ")
            if pendingControl != nil { advanceControlPreparation() } else { refreshNow() }; return
        }
        let domain = preparingDomains.removeFirst(); controlDomain = domain
        do {
            _ = try runtime.call("wireControlInit", ["domain": domain])
            let packet = try runtime.call("wireControlHandshake", ["domain": domain]) as? String ?? ""
            awaitingReply = true; try send(packet)
            timeout(16) { [weak self] in self?.responseTimedOut(op: "wireControlHandshake") }
        } catch { controlFailure(error.localizedDescription) }
    }
    func controlsReady(category: String) -> Bool {
        verifiedControlDomains.contains(category == "charge" || category == "climate" ? 3 : 2)
    }
    private func controlFailure(_ message: String) {
        guard !commandInFlight else { finishControl(uncertain: true, message: message); return }
        let domain = controlDomain ?? 3
        controlAuthFailures.append("\(domain == 3 ? "충전·공조" : "잠금·개폐") 인증: \(message)")
        trace(controlAuthFailures.last ?? message)
        _ = try? runtime.call("wireControlAbandon", ["domain": domain]); verifiedControlDomains.remove(domain)
        awaitingReply = false; deadline?.invalidate(); controlDomain = nil
        if writeInFlight || !chunks.isEmpty { finishControl(uncertain: false, message: message); return }
        continueControlAuthentication()
    }
    func askControl(_ action: String, title: String, args: Object = [:]) {
        // A manual tap supersedes only an unsent automation, never an in-flight command.
        cancelPendingAutomation()
        guard !commandUncertain else { controlStatus = "직전 명령 결과 미확인 · 실제 상태 확인 후 미확인 경고 해제 필요"; return }
        guard foreground, UIApplication.shared.applicationState == .active, authentic, controlEnabled, !commandInFlight, pendingControl == nil, confirmation == nil else { controlStatus = "조회 연결·제어 사용·앱 전면 상태 확인 필요"; return }
        let domain = ["lock", "unlock", "trunkMove", "trunkClose", "frunkOpen"].contains(action) ? 2 : 3
        guard verifiedControlDomains.contains(domain), !controlBusy else { prepareControlKeys(); controlStatus = "제어 인증 준비 중 · 완료 후 기능 버튼 사용 가능"; return }
        // A direct button tap is the user's one-time instruction. Never persist it
        // or carry it across authentication, connection or lifecycle changes.
        startControlIntent(action, title: title, args: args)
    }
    /// Only saved, explicitly enabled boarding HVAC rules may use this path.
    /// It cannot enroll a key, enable controls, retry a command, or queue through reconnection.
    func runAutomation(_ action: String, title: String, args: Object, authorized: @escaping () -> Bool, completion: @escaping (String) -> Void) -> String? {
        guard ["climateOn", "climateOff", "temperature"].contains(action) else { return "지원하지 않는 자동 제어" }
        guard authorized(), foreground, UIApplication.shared.applicationState == .active, authentic, controlEnabled else { return "탑승·정차·활성화 조건 미충족 · 건너뜀" }
        guard !commandUncertain else { return "직전 제어 결과 미확인 · 건너뜀" }
        guard !commandInFlight, pendingControl == nil, confirmation == nil, !controlBusy, automationCompletion == nil else { return "다른 제어 처리 중 · 건너뜀" }
        guard verifiedControlDomains.contains(3) else { return "공조 제어 인증 준비 전 · 건너뜀" }
        automationAuthorization = authorized; automationCompletion = completion
        automationGate = AutomationWriteGate(now: ProcessInfo.processInfo.systemUptime)
        startControlIntent(action, title: title, args: args)
        return nil
    }
    private func startControlIntent(_ action: String, title: String, args: Object) {
        pendingControl = (action, title, args, ProcessInfo.processInfo.systemUptime + 8)
        preparationTimer?.invalidate()
        let timer = Timer(timeInterval: 8, repeats: false) { [weak self] _ in
            guard let self, self.pendingControl != nil else { return }
            self.cancelConfirmation(); self.controlStatus = "정차 조회 준비 기한 만료 · 명령 전송 없음"
        }
        preparationTimer = timer; RunLoop.main.add(timer, forMode: .common)
        preparingControl = true; preparationNeedsDrive = automationAuthorization == nil
        controlStatus = "\(title) · 정차 상태 확인 후 1회 전송"
        trace("\(action) 선택 · 준비만 시작")
        advanceControlPreparation()
    }
    private func advanceControlPreparation() {
        guard let intent = pendingControl else { return }
        if let authorized = automationAuthorization, !authorized() { cancelConfirmation(); return }
        guard foreground, UIApplication.shared.applicationState == .active, authentic, controlEnabled, ProcessInfo.processInfo.systemUptime <= intent.until else {
            cancelConfirmation(); controlStatus = "준비 기한·연결 상태 변경 · 명령 전송 없음"; return
        }
        guard !awaitingReply, !writeInFlight, chunks.isEmpty, !controlBusy else { return }
        let domain = ["lock", "unlock", "trunkMove", "trunkClose", "frunkOpen"].contains(intent.action) ? 2 : 3
        if !verifiedControlDomains.contains(domain) { cancelConfirmation(); controlStatus = "인증 변경 · 선택한 명령 취소"; return }
        if automationAuthorization != nil {
            if let group = automationGate?.issueNext(now: ProcessInfo.processInfo.systemUptime) {
                request("wireQuery", ["group": group]); return
            }
            guard automationGate?.consume(now: ProcessInfo.processInfo.systemUptime, authorized: automationAuthorization?() == true, domainReady: verifiedControlDomains.contains(3)) == true else { cancelConfirmation(); return }
        }
        if preparationNeedsDrive { preparationNeedsDrive = false; request("wireQuery", ["group": "drive"]); return }
        do {
            _ = try runtime.call("controlContext", ["foreground": true, "enabled": controlEnabled])
            let ticket = try runtime.call("controlPrepare", ["action": intent.action, "args": intent.args]) as? String ?? ""
            guard !ticket.isEmpty else { throw LocalError.message("제어 확인 생성 실패") }
            preparationTimer?.invalidate(); preparationTimer = nil; pendingControl = nil; preparingControl = false
            let item = ControlConfirmation(id: ticket, action: intent.action, title: intent.title, args: intent.args, warning: "")
            confirmation = item
            executeConfirmed(item)
        } catch { cancelConfirmation(); controlStatus = error.localizedDescription; trace("제어 준비 중단 · \(error.localizedDescription)") }
    }
    private func executeConfirmed(_ item: ControlConfirmation) {
        guard confirmation?.id == item.id else { return }
        if let authorized = automationAuthorization, !authorized() { cancelConfirmation(); return }
        confirmation = nil
        guard foreground, UIApplication.shared.applicationState == .active, authentic, controlEnabled, !awaitingReply, !writeInFlight, chunks.isEmpty, !controlBusy else { cancelConfirmation(); controlStatus = "전송 조건이 변경됨 · 전송하지 않음"; return }
        do {
            // Gate consumes a one-use ticket and checks fresh authenticated P/speed again.
            let packet = try runtime.call("wireCommand", ["action": item.action, "args": item.args, "ticket": item.id]) as? String ?? ""
            controlDomain = ["lock", "unlock", "trunkMove", "trunkClose", "frunkOpen"].contains(item.action) ? 2 : 3
            commandInFlight = true; controlBusy = true; awaitingReply = true
            controlSpeechIntent = item
            UserDefaults.standard.set(true, forKey: "manualControlPending")
            controlStatus = "\(item.title) 요청 전송 중 · 차량 응답 대기"
            trace("\(item.action) \(automationAuthorization == nil ? "직접 선택" : "활성화된 탑승 규칙") · 명령 1회 전송")
            try send(packet)
            timeout(16) { [weak self] in self?.responseTimedOut(op: "wireCommand") }
        } catch { finishControl(uncertain: commandInFlight, message: error.localizedDescription) }
    }
    private func receiveControl(_ result: Object, domain: Int) {
        awaitingReply = false; deadline?.invalidate()
        if result.string("type") == "session", !commandInFlight {
            verifiedControlDomains.insert(domain); controlDomain = nil; continueControlAuthentication(); return
        }
        if result.string("type") == "commandAck" {
            UserDefaults.standard.set(false, forKey: "manualControlPending")
            finishControl(uncertain: false, message: "차량의 인증된 처리 응답 수신 · 동작 완료 여부는 상태값·실차 확인 필요", preserveSession: true, voiceResult: .accepted)
        } else if result.string("type") == "commandRejected" {
            UserDefaults.standard.set(false, forKey: "manualControlPending")
            finishControl(uncertain: false, message: result.string("reason"), voiceResult: .rejected)
        } else { finishControl(uncertain: commandInFlight, message: "제어 응답 형식 미확인") }
    }
    func mediaCommand(_ action: String, delta: Int = 0) {
        guard ["mediaToggle", "mediaNext", "mediaPrev", "mediaVolume"].contains(action) else { return }
        guard foreground, UIApplication.shared.applicationState == .active, authentic else { mediaStatus = "차량 연결 후 사용 가능"; return }
        guard controlEnabled else { mediaStatus = "연결 상태에서 ‘제어 사용’을 켜야 함"; return }
        guard verifiedControlDomains.contains(3) else { prepareControlKeys(); mediaStatus = "미디어 제어 인증 준비 중"; return }
        guard !commandInFlight, !awaitingReply, !writeInFlight, chunks.isEmpty, !controlBusy, pendingControl == nil, confirmation == nil else { mediaStatus = "다른 요청 처리 중 · 잠시 후 다시"; return }
        do {
            var args: Object = [:]
            if action == "mediaVolume" { args["delta"] = delta >= 0 ? 1 : -1 }
            let packet = try runtime.call("wireMediaCommand", ["action": action, "args": args]) as? String ?? ""
            controlDomain = 3; commandInFlight = true; controlBusy = true; awaitingReply = true; mediaInFlight = true
            mediaStatus = ""
            trace("미디어 \(action) · 1회 전송")
            try send(packet)
            timeout(8) { [weak self] in self?.responseTimedOut(op: "wireCommand") }
        } catch {
            if mediaInFlight { finishControl(uncertain: false, message: error.localizedDescription) } else { mediaStatus = error.localizedDescription }
        }
    }
    private func finishControl(uncertain requestedUncertain: Bool, message: String, preserveSession: Bool = false, voiceResult: ControlVoiceResult = .failed) {
        let media = mediaInFlight; mediaInFlight = false
        // A media tap can never leave the "result unknown" lock that blocks vehicle commands.
        let uncertain = media ? false : requestedUncertain
        let spokenIntent = media ? nil : controlSpeechIntent; controlSpeechIntent = nil
        trace("제어 응답 · \(message)\(uncertain ? " · 결과 미확인" : "")")
        if !preserveSession, let domain = controlDomain { _ = try? runtime.call("wireControlAbandon", ["domain": domain]); verifiedControlDomains.remove(domain) }
        deadline?.invalidate(); awaitingReply = false; controlDomain = nil; commandInFlight = false; controlBusy = false; preparingDomains = []
        preparationTimer?.invalidate(); preparationTimer = nil; pendingControl = nil; preparingControl = false; preparationNeedsDrive = false
        controlAuthRequested = false; controlAuthRetryAt = ProcessInfo.processInfo.systemUptime + 60
        if media {
            if voiceResult == .accepted { mediaStatus = "" } else { mediaStatus = message }
            if writeInFlight || !chunks.isEmpty { recoverTransport("제어 전송 중단 · 조회 연결 복구"); return }
            if authentic, foreground { burst.removeAll { $0 == "media" }; burst.insert("media", at: 0); poll() }
            return
        }
        if uncertain { commandUncertain = true; UserDefaults.standard.set(true, forKey: "manualControlUncertain") }
        controlStatus = message + (uncertain ? " · 결과 미확인 · 자동 재전송 안함" : "")
        completeAutomation(controlStatus)
        if let spokenIntent { onControlOutcome?(ControlVoice.message(action: spokenIntent.action, value: spokenIntent.args.number("value"), result: uncertain ? .unknown : voiceResult)) }
        if writeInFlight || !chunks.isEmpty { recoverTransport("제어 전송 중단 · 조회 연결 복구"); return }
        // Read-only follow-up, never repeats the command.
        if authentic, foreground { refreshNow() }
    }
    func connect(vin: String) {
        foreground = UIApplication.shared.applicationState == .active
        selectVehicle(vin); userDisconnected = false; retryCount = 0
        guard foreground else { return }
        beginConnection()
    }
    func resume(vin: String) {
        let alreadyActive = foreground
        foreground = true
        backgroundRead = false; backgroundWanted = false
        _ = try? runtime.call("controlContext", ["foreground": true, "enabled": controlEnabled])
        if !alreadyActive { userDisconnected = false; retryTimer?.invalidate(); retryTimer = nil }
        guard !vin.isEmpty, !userDisconnected else { return }
        if vin != wantedVIN { selectVehicle(vin); resetTransport() }
        guard !busy, retryTimer == nil else { return }
        if connected { if authentic { refreshNow(retryUnavailable: !alreadyActive) } else if !awaitingReply, !writeInFlight, chunks.isEmpty, !controlBusy { authenticate() }; return }
        retryCount = 0; beginConnection()
    }
    private func beginConnection() {
        guard foreground, !userDisconnected, !wantedVIN.isEmpty else { return }
        resetTransport()
        selectVehicle(wantedVIN)
        closuresSupported = true
        recoveryAttempts = 0; consecutiveTimeouts = 0; deferredGroups = []; timedOutGroups = []; groupRetryAt = [:]; currentReadGroup = ""; controlAuthRetryAt = 0
        sessionStartedAt = Date().timeIntervalSince1970 * 1000
        do {
            runtime.crypto.configure(wantedVIN); runtime.controlCrypto.configure(wantedVIN)
            expectedName = try runtime.call("wireInit", ["vin": wantedVIN]) as? String ?? ""
            trace("차량 연결 준비 · 저장된 키 사용")
            guard !expectedName.isEmpty else { throw LocalError.message("차량 식별 실패") }
            scanRequested = true; busy = true; status = "Bluetooth 준비 중"
            if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
            else if central?.state == .poweredOn { scan() }
            else { status = "Bluetooth 설정·권한 확인 필요"; busy = false }
        } catch { status = error.localizedDescription; busy = false }
    }
    private func scan() {
        guard scanRequested, foreground, !userDisconnected else { return }; scanRequested = false
        busy = true; refreshing = true; status = "최신화 중 · 근처 차량 검색"
        central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        timeout(30) { [weak self] in
            guard let self, self.foreground, self.peripheral == nil else { return }
            // Keep the foreground scan alive: approaching the vehicle must not
            // wait for another polling window. Background/manual stop cancels it.
            self.status = "차량 미발견 · 앱이 열린 동안 근처 차량 대기 · 저장값 표시"
        }
    }
    private func timeout(_ seconds: TimeInterval, _ action: @escaping () -> Void) {
        deadline?.invalidate(); let timer = Timer(timeInterval: seconds, repeats: false) { _ in action() }; deadline = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func disconnect() {
        userDisconnected = true; backgroundWanted = false; resetTransport(); status = "연결 해제됨 · 다시 열거나 연결을 눌러 최신화"
    }
    private func resetTransport() {
        lastReadGear = nil
        backgroundRead = false
        retryTimer?.invalidate(); retryTimer = nil
        invalidateControls(interrupted: commandInFlight)
        connected = false; authentic = false
        _ = try? runtime.call("wireAbandon")
        onReadAvailabilityChange?()
        scanRequested = false; pollTimer?.invalidate(); pollTimer = nil; deadline?.invalidate(); deadline = nil
        central?.stopScan(); if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil; writer = nil; reader = nil; chunks = []; writeInFlight = false; connected = false; authentic = false; busy = false; awaitingReply = false; pairing = false; status = "차량 연결 전"
        refreshing = false; burst = []; refreshedGroups = []; sessionStartedAt = 0
    }
    func pauseForBackground() {
        foreground = false; cancelConfirmation()
        _ = try? runtime.call("controlContext", ["foreground": false, "enabled": controlEnabled])
        if supportsBackgroundRead, connected, authentic, !controlBusy, !commandInFlight, !userDisconnected,
           UserDefaults.standard.object(forKey: "backgroundBLERead") == nil || UserDefaults.standard.bool(forKey: "backgroundBLERead") {
            backgroundRead = true; backgroundWanted = true
            status = "백그라운드 BLE 조회 유지 · iOS 허용 범위"
            trace("백그라운드 조회 유지 · 제어 취소")
            return
        }
        resetTransport(); status = "백그라운드 일시 중지 · 다시 열면 자동 최신화"
    }
    func resignActive() {
        foreground = false
        cancelConfirmation()
        _ = try? runtime.call("controlContext", ["foreground": false, "enabled": controlEnabled])
        // An in-flight action cannot be undone after transmission.
        if commandInFlight { resetTransport(); status = "앱 전환으로 제어 응답 확인 중단" }
    }
    private func recoverTransport(_ message: String) {
        trace("조회 연결 복구 · \(message)")
        if !foreground, backgroundWanted, !userDisconnected, let p = peripheral, central?.state == .poweredOn { backgroundReconnect(p); return }
        resetTransport(); status = message
        guard foreground, !userDisconnected, !wantedVIN.isEmpty, central?.state == .poweredOn else { return }
        let delays: [Double] = [2, 5, 10, 20, 30]
        let delay = delays[min(retryCount, delays.count - 1)]; retryCount += 1
        status = "\(message) · \(Int(delay))초 후 재검색"
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.retryTimer = nil; self?.beginConnection() }
        retryTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func refreshNow(retryUnavailable: Bool = false) {
        guard foreground, connected, authentic, !commandInFlight, !controlBusy, confirmation == nil else { return }
        if retryUnavailable { timedOutGroups = []; deferredGroups = []; groupRetryAt = [:]; closuresSupported = true }
        do { _ = try runtime.call("wireRefresh") }
        catch { fail("최신화 초기화 실패 · \(error.localizedDescription)"); return }
        // v29: keep sessionStartedAt from authentication; refresh must not blank verified values.
        refreshedGroups = []; burst = refreshGroups; refreshing = true; status = "최신화 중 · 차량 응답 대기"
        poll()
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { if scanRequested { scan() } else if foreground, !userDisconnected, !wantedVIN.isEmpty, !connected { beginConnection() } }
        else { resetTransport(); status = central.state == .unauthorized ? "Bluetooth 권한이 필요함" : "Bluetooth 사용 불가 · 켜지면 자동 재검색" }
    }
    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? p.name ?? ""
        guard foreground, !userDisconnected, name.lowercased() == expectedName.lowercased(), peripheral == nil else { return }
        central.stopScan(); deadline?.invalidate(); peripheral = p; p.delegate = self; status = "차량 연결 중"
        central.connect(p)
        timeout(20) { [weak self] in self?.recoverTransport("BLE 연결 시간 초과") }
    }
    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) { guard p == peripheral else { return }; status = "차량 서비스 확인 중"; p.discoverServices([service]) }
    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { guard p == peripheral else { return }; recoverTransport("차량 연결 실패") }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        guard p == peripheral else { return }
        if !foreground, backgroundWanted, !userDisconnected { backgroundReconnect(p); return }
        recoverTransport("연결 끊김 · 저장된 기록 유지")
    }
    /// v29: in background a scan without service UUIDs never reports results, so reuse the known peripheral.
    /// A pending CoreBluetooth connect has no timeout and completes when the car is back in range,
    /// even while the phone is locked (bluetooth-central background mode).
    private func backgroundReconnect(_ p: CBPeripheral) {
        trace("백그라운드 연결 끊김 · 차량 재접속 대기")
        let vin = wantedVIN
        resetTransport()
        backgroundWanted = true; wantedVIN = vin
        do {
            runtime.crypto.configure(vin); runtime.controlCrypto.configure(vin)
            expectedName = try runtime.call("wireInit", ["vin": vin]) as? String ?? ""
        } catch { status = error.localizedDescription; return }
        sessionStartedAt = Date().timeIntervalSince1970 * 1000
        peripheral = p; p.delegate = self; busy = true
        status = "백그라운드 · 차량 재접속 대기"
        central?.connect(p, options: nil)
    }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard p == peripheral else { return }
        guard error == nil, let s = p.services?.first(where: { $0.uuid == service }) else { fail(error?.localizedDescription ?? "Tesla 서비스 없음"); return }
        p.discoverCharacteristics([writeID, readID], for: s)
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard p == peripheral else { return }
        guard error == nil else { fail(error!.localizedDescription); return }
        writer = service.characteristics?.first(where: { $0.uuid == writeID }); reader = service.characteristics?.first(where: { $0.uuid == readID })
        guard let reader, let writer, writer.properties.contains(.write), reader.properties.contains(.notify) || reader.properties.contains(.indicate) else { fail("BLE 읽기·쓰기 특성 미지원"); return }
        p.setNotifyValue(true, for: reader)
    }
    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard p == peripheral else { return }
        guard error == nil, characteristic.isNotifying else { fail(error?.localizedDescription ?? "알림 구독 실패"); return }
        deadline?.invalidate(); connected = true; busy = false; status = "BLE 연결됨 · 조회 인증 중"
        if !foreground, backgroundWanted { backgroundRead = true }
        authenticate()
    }
    func authenticate() {
        guard connected, readAllowed, !controlBusy, confirmation == nil else { status = "먼저 차량 연결·제어 대기 상태 확인 필요"; return }
        guard !awaitingReply, !writeInFlight, chunks.isEmpty else { status = "현재 차량 응답·전송 대기 중"; return }
        cancelConfirmation()
        pairing = false; pollTimer?.invalidate(); authentic = false
        _ = try? runtime.call("wireRefresh"); onReadAvailabilityChange?()
        request("wireHandshake")
    }
    func enrollMonitorKey() {
        guard connected, foreground, !awaitingReply, !writeInFlight, chunks.isEmpty, !controlBusy, confirmation == nil else { status = "연결·응답 대기 상태 확인 필요"; return }
        pairing = true; authentic = false; pollTimer?.invalidate()
        _ = try? runtime.call("wireAbandon"); invalidateControls(interrupted: false); onReadAvailabilityChange?()
        do {
            let hex = try runtime.call("wireEnroll") as? String ?? ""
            try send(hex)
            status = "차량에서 키카드로 승인한 뒤 ‘승인 후 조회’를 눌러야 함"
        } catch { fail(error.localizedDescription) }
    }
    private func request(_ op: String, _ argument: Object = [:]) {
        guard !awaitingReply else { return }
        do {
            let hex = try runtime.call(op, argument) as? String ?? ""
            if op == "wireQuery" { currentReadGroup = argument.string("group") }
            awaitingReply = true; try send(hex)
            // JS pending TTL is 15 seconds. Never issue a new request before it expires.
            timeout(16) { [weak self] in self?.responseTimedOut(op: op) }
        } catch { awaitingReply = false; fail(error.localizedDescription) }
    }
    private func responseTimedOut(op: String) {
        guard awaitingReply else { return }
        if controlDomain != nil { controlFailure("차량 응답 시간 초과 · 자동 명령 재전송 없음"); return }
        do {
            guard (try runtime.call("wireExpire") as? Bool) == true else { fail("응답 기한 처리 실패 · 다시 연결 필요"); return }
        } catch { fail(error.localizedDescription); return }
        awaitingReply = false; responseTimeouts += 1; consecutiveTimeouts += 1
        guard op == "wireQuery", authentic, !writeInFlight, chunks.isEmpty else {
            recoverTransport("차량 응답 없음 · 키 승인·수면 상태 확인 필요"); return
        }
        // A silent data group must not repeatedly starve all following groups.
        // Retry these groups after cooldown, explicit refresh or a new connection.
        if currentReadGroup == "drive" || currentReadGroup == "location" {
            groupRetryAt[currentReadGroup] = ProcessInfo.processInfo.systemUptime + 2
        } else if !currentReadGroup.isEmpty {
            timedOutGroups.insert(currentReadGroup)
            groupRetryAt[currentReadGroup] = ProcessInfo.processInfo.systemUptime + 30
        }
        if pendingControl != nil { cancelConfirmation(); controlStatus = "정차 상태 조회 지연 · 명령 전송 없음" }
        if consecutiveTimeouts < 2 { status = "일부 조회 응답 지연 · 다음 항목 조회 유지"; poll(); return }
        guard recoveryAttempts < 1 else { recoverTransport("응답 지연 반복 · 연결 복구 중"); return }
        recoveryAttempts += 1; status = "응답 지연 · 조회 세션 재인증 1회"; authenticate()
    }
    private func send(_ hex: String) throws {
        guard let p = peripheral, writer != nil, chunks.isEmpty, !writeInFlight else { throw LocalError.message("BLE 전송 상태 오류") }
        let framed = try runtime.call("wireFrame", ["hex": hex]) as? String ?? ""
        let data = try Data(hex: framed), mtu = p.maximumWriteValueLength(for: .withResponse)
        guard mtu > 0 else { throw LocalError.message("BLE MTU 오류") }
        chunks = stride(from: 0, to: data.count, by: mtu).map { data.subdata(in: $0..<min($0 + mtu, data.count)) }
        sendNext()
    }
    private func sendNext() { guard let p = peripheral, let w = writer, !chunks.isEmpty, !writeInFlight else { return }; writeInFlight = true; p.writeValue(chunks.removeFirst(), for: w, type: .withResponse) }
    func peripheral(_ p: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard p == peripheral else { return }; writeInFlight = false
        if let error { recoverTransport(error.localizedDescription) } else {
            sendNext()
            if chunks.isEmpty, !writeInFlight { if controlBusy { continueControlAuthentication() } else if pendingControl != nil || !burst.isEmpty { poll() } }
        }
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard p == peripheral, characteristic.uuid == readID, let data = characteristic.value, error == nil else { return }
        do {
            let messages = try runtime.call("wirePush", ["hex": data.hexadecimal]) as? [String] ?? []
            for hex in messages {
                if pairing { continue } // Pairing acknowledgements do not establish authenticated data.
                guard awaitingReply else { continue }
                let result = try runtime.call(controlDomain == nil ? "wireReceive" : "wireControlReceive", ["hex": hex, "domain": controlDomain ?? 3]) as? Object ?? [:]
                // Correlation noise is not an authenticated reply and does not finish this request.
                if result.string("type") == "ignored" { ignoredReplies += 1; continue }
                if result.string("type") == "progress" { continue }
                if let domain = controlDomain { receiveControl(result, domain: domain); continue }
                awaitingReply = false; deadline?.invalidate()
                consecutiveTimeouts = 0
                if result.string("type") == "session" {
                    authentic = true; status = "인증됨 · 차량 상태 수신 중"
                    trace("조회 인증 완료")
                    _ = try? runtime.call("controlContext", ["foreground": foreground, "enabled": controlEnabled])
                    queryIndex = 0; startPolling(); refreshNow()
                } else if result.string("type") == "data" {
                    protocolResyncs = 0
                    let snapshot = result.object("snapshot")
                    for (k, v) in snapshot.object("groups") { telemetryGroups[k] = v }
                    let drive = snapshot.object("groups").object("drive"), gear = drive.string("gear")
                    let receipt = Date().timeIntervalSince1970 * 1000
                    if VehicleReadPlan.enteredPark(previous: lastReadGear, gear: gear, at: drive.number("at"), now: receipt) {
                        burst.removeAll { $0 == "location" || $0 == "closures" || $0 == "charge" || $0 == "climate" }
                        burst.insert("climate", at: 0)
                        burst.insert("charge", at: 0)
                        burst.insert("closures", at: 0)
                        burst.insert("location", at: 0)
                        SmartParkingManager.shared.onVehicleParked(vehicleTelemetry: telemetryGroups)
                    }; burst.insert("location", at: 0)
                        SmartParkingManager.shared.onVehicleParked(latitude: nil, longitude: nil, currentSOC: nil)
                    }
                    if let at = drive.number("at"), at <= receipt + 5000, receipt - at <= 30000, ["P", "D", "R", "N"].contains(gear) { lastReadGear = gear }
                    retryCount = 0
                    refreshedGroups.formUnion(snapshot.object("groups").keys)
                    status = "차량 수신 중 · \(refreshedGroups.count)/\(VehicleReadPlan.groupCount)항목"
                    // Mark only responses to an already-issued preparation query, before a snapshot can create a new intent.
                    automationGate?.receive(groups: Set(snapshot.object("groups").keys), now: ProcessInfo.processInfo.systemUptime)
                    onSnapshot?(snapshot)
                    if burst.isEmpty { refreshing = false; status = "최신화 조회 완료 · \(refreshedGroups.count)/\(VehicleReadPlan.groupCount)항목 수신" }
                    if pendingControl != nil { advanceControlPreparation() }
                    else if !burst.isEmpty { poll() }
                    else if backgroundRead {
                        // BLE delegate wake → short read follow-up, not a promise
                        // of an unrestricted background timer or forced relaunch.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                            guard let self, self.backgroundRead else { return }; self.poll()
                        }
                    }
                }
                else if result.string("type") == "resync" {
                    cancelConfirmation(); protocolResyncs += 1
                    trace("조회 세션 재동기화 · 명령 재전송 없음")
                    if protocolResyncs > 2 { recoverTransport("세션 동기화 반복 · 연결 복구"); return }
                    burst.insert(result.string("group", "drive"), at: 0); poll()
                }
                else if result.string("type") == "queryRejected" {
                    let group = result.string("group")
                    deferredGroups.insert(group)
                    groupRetryAt[group] = ProcessInfo.processInfo.systemUptime + 120
                    if pendingControl != nil { cancelConfirmation(); controlStatus = "\(group) 조회 거절 · 제어 준비 취소" }
                    if group == "closures" { closuresSupported = false }
                    status = "\(group) 조회 거절 · 잠시 뒤 재조회, 기타 조회 유지"
                }
                else { fail("알 수 없는 차량 응답 · 조회 중단") }
            }
        } catch { if controlDomain != nil { controlFailure(error.localizedDescription) } else { awaitingReply = false; fail(error.localizedDescription) } }
    }
    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
        pollTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func poll() {
        guard readAllowed, authentic, !awaitingReply, !writeInFlight, chunks.isEmpty, !controlBusy, confirmation == nil, !pairing else { return }
        let now = ProcessInfo.processInfo.systemUptime
        for group in Array(groupRetryAt.keys) where (groupRetryAt[group] ?? .infinity) <= now {
            groupRetryAt.removeValue(forKey: group); timedOutGroups.remove(group); deferredGroups.remove(group)
        }
        if pendingControl != nil { advanceControlPreparation(); return }
        // A healthy Tesla session has no artificial periodic expiry. Authenticate
        // missing domains only; resync/failure explicitly invalidates affected state.
        if foreground, controlEnabled, burst.isEmpty, controlAuthRequested || (verifiedControlDomains.count < 2 && now >= controlAuthRetryAt) { startControlAuthentication(); return }
        while let first = burst.first { burst.removeFirst(); if !deferredGroups.contains(first), !timedOutGroups.contains(first) { request("wireQuery", ["group": first]); return } }
        refreshing = false
        let groups = VehicleReadPlan.regular.filter { !deferredGroups.contains($0) && !timedOutGroups.contains($0) }
        guard !groups.isEmpty else {
            if !timedOutGroups.isEmpty { recoverTransport("모든 상태 응답이 지연됨 · 연결 복구") }
            else { fail("모든 상태 조회가 거절됨 · 키 권한 확인 후 다시 연결 필요") }
            return
        }
        request("wireQuery", ["group": groups[queryIndex % groups.count]]); queryIndex += 1
    }
    private func fail(_ message: String) {
        trace("조회 오류 · \(message)")
        // Transport/protocol errors must not leave an idle, unauthenticated link.
        // Registration/permission failures require explicit vehicle approval.
        let needsApproval = message.contains("키 미등록") || message.contains("키 권한") || message.contains("not registered")
        if !needsApproval, foreground, !userDisconnected, !wantedVIN.isEmpty {
            recoverTransport(message); return
        }
        // Never reuse a transport with an unfinished write. A healthy idle BLE
        // link stays available for explicit key enrollment/manual authentication.
        if writeInFlight || !chunks.isEmpty { resetTransport() }
        deadline?.invalidate(); deadline = nil; pollTimer?.invalidate(); pollTimer = nil
        authentic = false
        _ = try? runtime.call("wireAbandon")
        onReadAvailabilityChange?()
        invalidateControls(interrupted: commandInFlight)
        status = message; busy = false; authentic = false; awaitingReply = false; pairing = false; refreshing = false
    }
}
