import SwiftUI
import Combine
import UniformTypeIdentifiers
import AVFoundation
import UserNotifications
import Vision
import ImageIO

final class AppModel: ObservableObject {
    static var shared: AppModel! = nil
    @Published var chargingPresented = false
    let fleet = TeslaFleetClient.shared
    let chargeNotifications = ChargeNotificationManager.shared
    let runtime: LocalRuntime
    let link: VehicleLink
    let navigation: EmbeddedNavigation
    let automations: AutomationCoordinator
    let aiRules = AutomationAI()
    let voice = VoiceCoordinator()
    @Published var output: Object = [:]
    @Published private(set) var archiveReadings: [FleetTelemetryReading] = []
    @Published var errorMessage: String?
    @Published private(set) var storageStatus: String?
    @Published var demo = false
    @Published var sharedFile: URL?
    var vehicleReference: Object {
        let vin = fleet.selectedVin.isEmpty ? settings.string("vin") : fleet.selectedVin
        return UserDefaults.standard.dictionary(forKey: "vehicle.reference." + vin) ?? [:]
    }
    var displayOdometerKm: Double? {
        let vin = fleet.selectedVin.isEmpty ? settings.string("vin") : fleet.selectedVin
        var values = [vehicleReference.number("odometerKm")]
        if settings.string("vin") == vin { values.append(groups.object("drive").number("odometerKm")) }
        if let snapshot = fleet.vehicleSnapshot, snapshot.vin == vin { values.append(snapshot.number("vehicle_state", "odometer").map { $0 * 1.609344 }) }
        if !demo, let reading = FleetTelemetryData.latest(archiveReadings, vin: vin)["Odometer"], !reading.invalid { values.append(reading.number.map { $0 * 1.609344 }) }
        return values.compactMap { $0 }.filter { $0.isFinite && $0 >= 0 }.max()
    }
    /// v92: the 주차 중 / 정차 중 badge flickered to 상태 미수신 between polls.
    /// A parked car does not change state while nothing is reporting, so the last
    /// observed gear is kept and handed back when no current source carries one.
    /// It is a cache of something the vehicle said, not an inference: the reading
    /// keeps the timestamp it was observed at, so the screen still shows its age,
    /// and it is cleared whenever a source does report a gear.
    func rememberMotion(_ drive: Object) -> Object {
        let vin = fleet.selectedVin.isEmpty ? settings.string("vin") : fleet.selectedVin
        guard !vin.isEmpty, !demo else { return drive }
        let key = "motion.last." + vin
        if !drive.string("gear").isEmpty, let at = drive.number("at") {
            let stored: [String: Any] = ["gear": drive.string("gear"), "at": at,
                                         "speedKmh": drive.number("speedKmh") ?? 0]
            if (UserDefaults.standard.dictionary(forKey: key)?["at"] as? Double) != at {
                UserDefaults.standard.set(stored, forKey: key)
            }
            return drive
        }
        guard let remembered = UserDefaults.standard.dictionary(forKey: key),
              let at = remembered["at"] as? Double, let gear = remembered["gear"] as? String else { return drive }
        // Only fill the gap: anything the live group did carry stays untouched.
        var merged = drive
        merged["gear"] = gear
        if merged.number("speedKmh") == nil { merged["speedKmh"] = remembered["speedKmh"] as? Double ?? 0 }
        if merged.number("at") == nil { merged["at"] = at }
        merged["mode"] = "cached"
        merged["motionFromMemory"] = true
        return merged
    }
    var isSpeaking: Bool { voice.speaking }
    @Published var receiptDraft: Object = [:]
    @Published var receiptText = ""
    @Published var ocrBusy = false
    private var liveState: Object?
    private var receiptRequest = UUID()
    private let folder: URL
    private let recordFile: URL
    private var lastSaved = Date.distantPast
    private var recoveryLock = false
    private var timer: Timer?
    private var fleetObservation: AnyCancellable?
    private var archiveObservation: AnyCancellable?
    private var lastArchiveSync = Date.distantPast
    private var lastFleetPoll = Date.distantPast
    private var protectedDataObserver: NSObjectProtocol?
    private var savePending = false
    private var handedOffRoute = ""
    private var protectedLoadPending = false
    private var nextSaveAttempt = Date.distantPast
    var state: Object { output.object("state") }
    var groups: Object { state.object("groups") }
    var settings: Object { state.object("settings") }
    init() throws {
        UserDefaults.standard.register(defaults: ["keepDriveDisplayOn": true])
        runtime = try LocalRuntime(); link = VehicleLink(runtime: runtime)
        navigation = EmbeddedNavigation(runtime: runtime)
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("YLCompanion", isDirectory: true)
        recordFile = folder.appendingPathComponent("records.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        automations = try AutomationCoordinator(folder: folder)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var localFolder = folder; try localFolder.setResourceValues(values)
        if FileManager.default.fileExists(atPath: recordFile.path) {
            let lockedReadable = ((try? FileManager.default.attributesOfItem(atPath: recordFile.path)[.protectionKey]) as? FileProtectionType) == .completeUntilFirstUserAuthentication
            if UIApplication.shared.isProtectedDataAvailable || lockedReadable {
                do { _ = try runtime.call("load", ["state": decodeJSON(String(contentsOf: recordFile, encoding: .utf8)), "resume": true]) }
                catch { recoveryLock = true; errorMessage = "저장 자료를 읽지 못함. 원본 보호를 위해 저장을 잠금. 백업 복원 필요. \(error.localizedDescription)" }
            } else {
                protectedLoadPending = true; recoveryLock = true
                storageStatus = "기록 불러오기 대기 · 기기 잠금 해제 후 기존 자료를 엶"
            }
        }
        automations.onNotification = { id, title, body in
            Task { @MainActor in ChargeNotificationManager.shared.notifyAutomation(id: id, title: title, body: body) }
        }
        refresh()
        fleet.commandAllowed = { [weak self] in
            guard let self else { return false }
            return !self.demo && UIApplication.shared.applicationState == .active && !self.link.controlBusy && !self.link.preparingControl && self.link.confirmation == nil
        }
        fleet.onCommandFailure = { [weak self] text in self?.errorMessage = text }
        fleet.onVehicleSnapshot = { [weak self] snapshot in
            guard let self, !self.demo, snapshot.vin == self.fleet.selectedVin else { return }
            let previousTrips = self.state.rows("trips").count
            defer {
                self.finishObservedTrip(previousCount: previousTrips)
                let history = self.state
                Task { @MainActor in
                    self.automations.observeFleetSpeech(snapshot, history: history, previousTrips: previousTrips, link: self.link, voice: self.voice)
                    self.automations.observeFleet(snapshot, voice: self.voice, bleActive: self.link.authentic)
                }
            }
            let bleDrive = self.groups.object("drive")
            let fleetDriveAt = snapshot.number("drive_state", "timestamp") ?? 0
            if snapshot.sectionIsRecent("drive_state"), !self.link.authentic || fleetDriveAt > (bleDrive.number("at") ?? 0) {
                let overlay = snapshot.homeOverlay()
                let history: Object = ["vin": snapshot.vin, "drive": snapshot.driveDisplay(), "charge": overlay["charge"] ?? Object(), "location": overlay["location"] ?? Object()]
                do { self.output = try self.runtime.call("ingestFleetDrive", history) as? Object ?? self.output; self.saveRecordsWhenAvailable() }
                catch { self.storageStatus = "Fleet 운행 기록 저장: " + error.localizedDescription }
            }
            guard snapshot.sectionIsRecent("charge_state"),
                  let charge = snapshot.payload["charge_state"] as? Object,
                  let status = charge["charging_state"] as? String,
                  let state = ["Disconnected": 2, "NoPower": 3, "Starting": 4, "Charging": 5, "Complete": 6, "Stopped": 7, "Calibrating": 8][status] else { return }
            var input: Object = ["vin": snapshot.vin, "charging": state]
            input["at"] = snapshot.number("charge_state", "timestamp")
            input["soc"] = snapshot.soc; input["limit"] = snapshot.number("charge_state", "charge_limit_soc")
            input["addedKWh"] = snapshot.number("charge_state", "charge_energy_added")
            if charge["fast_charger_present"] as? Bool == true {
                let brand = (charge["fast_charger_brand"] as? String) ?? ""
                input["chargeType"] = brand.lowercased().contains("tesla") || brand.lowercased().contains("supercharger") ? "supercharger" : "dc"
                input["chargeOperator"] = brand
            } else if let phases = snapshot.number("charge_state", "charger_phases"), phases > 0 { input["chargeType"] = "ac" }
            if snapshot.sectionIsRecent("drive_state") {
                input["latitude"] = snapshot.number("drive_state", "latitude"); input["longitude"] = snapshot.number("drive_state", "longitude")
            }
            do { self.output = try self.runtime.call("ingestFleetCharge", input) as? Object ?? self.output; self.saveRecordsWhenAvailable() }
            catch { self.storageStatus = "Fleet 충전 기록 저장: " + error.localizedDescription }
        }
        fleetObservation = fleet.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send(); self?.considerNavigation(); self?.observeParkingTelemetry() }
        }
        Task { @MainActor [weak self] in
        FleetArchiveClient.shared.onHistoryReady = { [weak self] vin in
            guard let self, !self.demo, self.fleet.selectedVin == vin else { throw CancellationError() }
            try self.mergeArchiveHistory(vin: vin)
            try self.persist()
            FleetTelemetryStore.shared.historySaved(vin: vin)
        }
        }
        archiveObservation = FleetTelemetryStore.shared.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { guard let self else { return }; self.archiveReadings = FleetTelemetryStore.shared.records; self.observeParkingTelemetry() } }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.archiveReadings = FleetTelemetryStore.shared.records
            self.observeParkingTelemetry()
            do { try self.enrichLocalChargeSOC(); self.saveRecordsWhenAvailable() }
            catch { self.storageStatus = "충전 배터리 기록 보완: " + error.localizedDescription }
        }
        automations.settingsDidChange = { [weak self] in self?.voice.stopAutomatic(); self?.link.cancelPendingAutomation() }
        navigation.canPresent = { [weak self] in
            guard let self else { return false }
            // v29: informational alerts (errorMessage) no longer block navigation start.
            return !self.demo && !self.aiRules.presented && UIApplication.shared.applicationState == .active && !self.link.controlBusy && !self.link.preparingControl && self.sharedFile == nil
        }
        navigation.willStart = { [weak self] in self?.stopSpeech() }
        navigation.onVoiceActivity = { [weak self] active in self?.voice.nativeVoice(active) }
        navigation.onGuidanceEnd = { [weak self] in
            self?.voice.stop()
            self?.voice.navigationGuide("경로 안내 종료.", safety: false)
        }
        navigation.onSpokenGuide = { [weak self] text, safety in self?.voice.navigationGuide(text, safety: safety) }
        navigation.onPrepareGuide = { [weak self] message in self?.voice.prepareNavigation(message) }
        voice.navigationTargetIsAhead = { [weak self] identifier in self?.navigation.isSpeechTargetAhead(identifier) == true }
        navigation.onAudioSession = { [weak self] active in self?.voice.nativeSession(active) }
        link.onControlOutcome = { [weak self] message in
            self?.voice.say(message, key: "controlOutcome:" + UUID().uuidString, category: "voiceControl", priority: 2)
        }
        link.onSnapshot = { [weak self] snapshot in
            guard let self, !self.demo else { return }
            do {
                let previousCount = self.state.rows("trips").count
                let previousCharges = self.state.rows("charges").count
                self.output = try self.runtime.call("ingest", snapshot) as? Object ?? [:]
                let charging = snapshot.object("groups").object("charge")
                if let raw = charging.number("charging"), let status = ChargeEventPolicy.bleState(Int(raw)), let at = charging.number("at") {
                    let observation = ChargeObservation(vin: self.settings.string("vin"), at: Date(timeIntervalSince1970: at / 1000), state: status, soc: charging.number("soc"), limit: charging.number("limit"))
                    Task { @MainActor in ChargeNotificationManager.shared.observe(observation) }
                }
                if snapshot.object("groups")["drive"] != nil {
                    self.considerNavigation()
                    let d = snapshot.object("groups").object("drive")
                    let gear = d.string("gear")
                    let speed = d.number("speedKmh") ?? 0
                    // Note: Once userDismissed is set manually by user, it only reopens when manually tapped
                    if (gear == "D" || gear == "R" || speed > 5), !self.navigation.presented, !self.navigation.userDismissed, UIApplication.shared.applicationState == .active {
                        if UserDefaults.standard.object(forKey: "autoDrivingDashboard") == nil || UserDefaults.standard.bool(forKey: "autoDrivingDashboard") {
                            self.navigation.activateWorkspace(model: self)
                        }
                    }
                }
                if self.state.rows("trips").count > previousCount || self.state.rows("charges").count > previousCharges || Date().timeIntervalSince(self.lastSaved) > 5 { self.saveRecordsWhenAvailable() }
                self.finishObservedTrip(previousCount: previousCount)
                self.automations.observe(output: self.output, previousTrips: previousCount, previousCharges: previousCharges, link: self.link, voice: self.voice, demo: self.demo)
            } catch {
                self.automations.resetObservation(); self.link.cancelPendingAutomation()
                self.errorMessage = error.localizedDescription
            }
        }
        link.onReadAvailabilityChange = { [weak self] in
            guard let self else { return }
            self.output["fresh"] = Object(); self.refresh()
            if !self.link.authentic { self.automations.resetObservation() } // BLE loss must not cancel already-valid Fleet or navigation speech.
        }
        protectedDataObserver = NotificationCenter.default.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { [weak self] _ in
            self?.loadProtectedRecordsIfNeeded()
            self?.nextSaveAttempt = .distantPast
            if self?.savePending == true { self?.saveRecordsWhenAvailable() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
            self?.syncArchiveIfNeeded()
            // Fleet API is billed per call and can wake the car: poll every 30 s, not every 5 s timer tick.
            if let self, !self.demo, !self.link.authentic, UIApplication.shared.applicationState == .active, Date().timeIntervalSince(self.lastFleetPoll) >= 30 {
                self.lastFleetPoll = Date()
                Task { @MainActor in await self.fleet.refreshVehicleSnapshot() }
            }
            if self?.savePending == true { self?.saveRecordsWhenAvailable() }
        }
    }
    deinit {
        timer?.invalidate()
        if let protectedDataObserver { NotificationCenter.default.removeObserver(protectedDataObserver) }
    }
    private func syncArchiveIfNeeded() {
        Task { @MainActor in
        guard !demo, UIApplication.shared.applicationState == .active,
              Date().timeIntervalSince(lastArchiveSync) >= 30, !FleetArchiveClient.shared.address.isEmpty,
              !fleet.selectedVin.isEmpty else { return }
        lastArchiveSync = Date()
        let vin = fleet.selectedVin
            await FleetArchiveClient.shared.sync(vin: vin)
            if let observation = FleetTelemetryData.chargeObservation(FleetTelemetryStore.shared.records, vin: vin) { ChargeNotificationManager.shared.observe(observation) }
            guard !self.demo, self.fleet.selectedVin == vin else { return }
            do { try self.mergeArchiveHistory(vin: vin); self.saveRecordsWhenAvailable() }
            catch { self.storageStatus = "NAS 기록 통합: " + error.localizedDescription }
        }
    }
    @MainActor private func mergeArchiveHistory(vin: String) throws {
        let store = FleetTelemetryStore.shared
        guard let since = store.pendingHistoryStart(vin: vin) else { return }
        let window = FleetTelemetryData.historyWindow(store.records, vin: vin, since: since)
        let rows: [Object] = window.rows.map { r in
            var value: Object = ["at": r.at.timeIntervalSince1970 * 1000, "field": r.field, "text": r.text, "invalid": r.invalid]
            if let n = r.number { value["number"] = n }; return value
        }
        guard !rows.isEmpty else { return }
        output = try runtime.call("ingestArchive", ["vin": vin, "rows": rows, "replayFrom": window.start.timeIntervalSince1970 * 1000]) as? Object ?? output
        archiveReadings = store.records
        try enrichLocalChargeSOC()
    }
    func refresh() {
        do {
            // Read loaded settings before migrating the older standalone preference.
            output = try runtime.call("view") as? Object ?? [:]
            if !demo && !recoveryLock {
                let defaults = UserDefaults.standard
                var rates: Object = [:]
                if settings.number("tariff") != nil { defaults.set(true, forKey: "cost.legacyTariffMigrated") }
                if !defaults.bool(forKey: "cost.legacyTariffMigrated"), settings.number("tariff") == nil,
                   let legacy = defaults.string(forKey: "cost.electricity").flatMap(Double.init), legacy.isFinite, (0...10000).contains(legacy) { rates["tariff"] = legacy }
                if let data = defaults.data(forKey: "navigation.home"), let home = try? JSONSerialization.jsonObject(with: data) as? Object,
                   let lat = home.number("latitude"), let lon = home.number("longitude"), (-90...90).contains(lat), (-180...180).contains(lon), !(lat == 0 && lon == 0),
                   settings.object("homePoint").number("latitude") != lat || settings.object("homePoint").number("longitude") != lon {
                    rates["homePoint"] = ["latitude": lat, "longitude": lon]
                }
                if !rates.isEmpty {
                    _ = try runtime.call("settings", rates)
                    if rates["tariff"] != nil { defaults.set(true, forKey: "cost.legacyTariffMigrated") }
                    output = try runtime.call("view") as? Object ?? [:]
                }
            }
            if !link.connected || !link.authentic { output["fresh"] = Object() }
        } catch { output["fresh"] = Object(); errorMessage = error.localizedDescription }
    }
    private func persist() throws {
        guard !demo else { return }
        guard !recoveryLock else { throw LocalError.message("원본 기록 보호 중. 정상 백업을 복원하기 전에는 저장하지 않음.") }
        // v29: records use completeUntilFirstUserAuthentication, so saving works under the lock screen after first unlock.
        guard UIApplication.shared.isProtectedDataAvailable || canWriteLocked() else { throw LocalError.message("기기 잠금 해제 후 기록 저장 가능함") }
        let data = Data(try encodeJSON(runtime.call("export")).utf8)
        try data.write(to: recordFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        lastSaved = Date(); savePending = false; storageStatus = nil; nextSaveAttempt = .distantPast
    }
    private func canWriteLocked() -> Bool {
        let level = (try? FileManager.default.attributesOfItem(atPath: recordFile.path)[.protectionKey]) as? FileProtectionType
        return level == .completeUntilFirstUserAuthentication || level == FileProtectionType.none
    }
    private func loadProtectedRecordsIfNeeded() {
        guard protectedLoadPending, UIApplication.shared.isProtectedDataAvailable else { return }
        do {
            _ = try runtime.call("load", ["state": decodeJSON(String(contentsOf: recordFile, encoding: .utf8)), "resume": true])
            protectedLoadPending = false; recoveryLock = false; storageStatus = nil
            refresh(); resume()
        } catch {
            protectedLoadPending = false; recoveryLock = true
            errorMessage = "저장 자료를 읽지 못함. 원본 보호를 위해 저장을 잠금. 백업 복원 필요. \(error.localizedDescription)"
        }
    }
    // Storage failure must not cancel live telemetry, navigation or automation.
    // Keep only the current runtime state pending; never overwrite a protected original with defaults.
    private func saveRecordsWhenAvailable() {
        guard !demo, !recoveryLock else { return }
        savePending = true
        guard UIApplication.shared.isProtectedDataAvailable || canWriteLocked() else {
            storageStatus = "기록 저장 대기 · 잠금 해제 후 재시도. 저장 전 앱 종료 시 최근 기록이 유실될 수 있음"
            return
        }
        guard Date() >= nextSaveAttempt else { return }
        do { try persist() }
        catch {
            nextSaveAttempt = Date().addingTimeInterval(30)
            storageStatus = "기록 저장 실패 · 최근 변경은 아직 저장되지 않음. 30초 후 재시도"
        }
    }
    private func observeParkingTelemetry() {
        guard !demo else { return }
        let vin = fleet.selectedVin.isEmpty ? settings.string("vin") : fleet.selectedVin
        SmartParkingManager.shared.observeVehicleTelemetry(homePresentation(self, link), vin: vin)
    }
    private func enrichLocalChargeSOC() throws {
        guard !demo else { return }
        let vin = settings.string("vin")
        let intervals = state.rows("charges").filter { $0.number("end") != nil }
        let rows: [Object] = archiveReadings.filter { r in
            r.vin == vin && ["Soc", "BatteryLevel"].contains(r.field) && intervals.contains { c in
                let stamp = r.at.timeIntervalSince1970 * 1000
                return abs(stamp - (c.number("at") ?? 0)) <= 120000 || abs(stamp - (c.number("end") ?? 0)) <= 120000
            }
        }.map { r in
            var value: Object = ["at": r.at.timeIntervalSince1970 * 1000, "invalid": r.invalid]
            if let soc = r.number { value["soc"] = soc }; return value
        }
        guard !rows.isEmpty else { return }
        output = try runtime.call("enrichChargeSOC", ["vin": vin, "rows": rows]) as? Object ?? output
    }
    func mutate(_ operation: String, _ value: Object = [:]) {
        guard !recoveryLock || demo else { errorMessage = "원본 기록 보호 중. 백업 복원 필요."; return }
        do {
            let previousVIN = settings.string("vin")
            _ = try runtime.call(operation, value); refresh()
            if ["addCharge", "updateCharge"].contains(operation) { try enrichLocalChargeSOC() }
            if settings.string("vin") != previousVIN { navigation.reset(); automations.resetObservation(); link.cancelPendingAutomation() }
            saveRecordsWhenAvailable()
        }
        catch { errorMessage = error.localizedDescription }
    }
    func enterDemo() {
        guard !demo else { return }; navigation.reset(); automations.resetObservation(); link.disconnect()
        do { liveState = try runtime.call("export") as? Object; demo = true; output = try runtime.call("demo") as? Object ?? [:] }
        catch { errorMessage = error.localizedDescription }
    }
    func exitDemo() {
        guard demo, let previous = liveState else { return }
        do { output = try runtime.call("load", ["state": previous, "resume": true]) as? Object ?? [:]; demo = false; liveState = nil; resume() }
        catch { errorMessage = error.localizedDescription }
    }
    func connect() {
        guard !recoveryLock else { errorMessage = "원본 기록 보호 중. 백업 복원 필요."; return }
        guard !demo else { errorMessage = "예시 모드를 종료한 뒤 실차에 연결해야 함"; return }
        link.connect(vin: settings.string("vin"))
    }
    func pause() { link.pauseForBackground(); saveRecordsWhenAvailable() }
    func resignActive() { link.resignActive(); navigation.suspendPending() }
    func resume() {
        guard !recoveryLock, !demo, UIApplication.shared.applicationState == .active else { return }
        nextSaveAttempt = .distantPast
        if savePending { saveRecordsWhenAvailable() }
        link.resume(vin: settings.string("vin")); navigation.foregrounded(); refresh()
        Task { @MainActor in await fleet.refreshVehicleSnapshot() }
    }
    func refreshVehicle() {
        guard !recoveryLock, !demo else { return }
        if link.authentic { link.refreshNow(retryUnavailable: true) }
        if fleet.isAuthenticated { Task { @MainActor in await fleet.refreshVehicleSnapshot(force: true) } }
        if !link.authentic && !fleet.isAuthenticated { connect() }
        refresh()
    }
    func speak(_ text: String? = nil) {
        let fresh = output.object("fresh")
        let prefix = ""
        voice.say(prefix + (text ?? output.string("briefing")), key: "manual", category: "", priority: 2, ttl: 20, manual: true)
    }
    func stopSpeech() { voice.stop() }

    /// v39: hand the vehicle's destination to Naver Map. Its own guidance voice (including the celebrity
    /// voices Naver licenses) then speaks the turns — this app cannot synthesise a real person's voice,
    /// but it can put the destination into the app that already has one.
    func openInNaverMap() {
        guard !demo else { errorMessage = "예시 모드에서는 길안내를 넘기지 않음"; return }
        do {
            let value = try runtime.call("navigation", ["appname": Bundle.main.bundleIdentifier ?? "ylcompanion"])
            guard let text = value as? String, let url = URL(string: text) else { throw LocalError.message("목적지 주소를 만들지 못함") }
            UIApplication.shared.open(url, options: [:]) { [weak self] opened in
                guard !opened else { return }
                DispatchQueue.main.async {
                    self?.errorMessage = "네이버 지도를 열지 못함 · App Store에서 설치한 뒤 다시 시도"
                    if let store = URL(string: "https://apps.apple.com/kr/app/id311867728") { UIApplication.shared.open(store) }
                }
            }
            // Naver speaks the turns from here on; this app going on talking over it helps nobody.
            voice.stop()
        } catch { errorMessage = error.localizedDescription }
    }
    func openInTMap() {
        guard !demo else { errorMessage = "예시 모드에서는 길안내를 넘기지 않음"; return }
        let d = groups.object("drive")
        guard let lat = d.number("destinationLat"), let lng = d.number("destinationLng"), lat != 0, lng != 0 else {
            errorMessage = "목적지 좌표 미수신 · 차량 내비 목적지 설정 필요"
            return
        }
        let name = (d.string("destination").isEmpty ? "목적지" : d.string("destination")).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "목적지"
        if let url = URL(string: "tmap://route?goalname=\(name)&goallat=\(lat)&goallng=\(lng)") {
            UIApplication.shared.open(url, options: [:]) { [weak self] opened in
                if opened { self?.voice.stop() }
                else if let store = URL(string: "https://apps.apple.com/kr/app/id431589174") { UIApplication.shared.open(store) }
            }
        }
    }
    func openInKakaoNavi() {
        guard !demo else { errorMessage = "예시 모드에서는 길안내를 넘기지 않음"; return }
        let d = groups.object("drive")
        guard let lat = d.number("destinationLat"), let lng = d.number("destinationLng"), lat != 0, lng != 0 else {
            errorMessage = "목적지 좌표 미수신 · 차량 내비 목적지 설정 필요"
            return
        }
        let name = (d.string("destination").isEmpty ? "목적지" : d.string("destination")).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "목적지"
        if let url = URL(string: "kakaonavi://navigate?name=\(name)&x=\(lng)&y=\(lat)&coord_type=wgs84") {
            UIApplication.shared.open(url, options: [:]) { [weak self] opened in
                if opened { self?.voice.stop() }
                else if let store = URL(string: "https://apps.apple.com/kr/app/id417698864") { UIApplication.shared.open(store) }
            }
        }
    }
    private func finishObservedTrip(previousCount: Int) {
        guard !demo, state.rows("trips").count > previousCount,
              let trip = state.rows("trips").last, let end = trip.number("end"),
              abs(Date().timeIntervalSince1970 * 1000 - end) <= 120000 else { return }
        navigation.endGuidance()
        let vin = fleet.selectedVin.isEmpty ? settings.string("vin") : fleet.selectedVin
        let body = state.string("lastBrief")
        let id = trip.string("id")
        Task { @MainActor in chargeNotifications.notifyTrip(vin: vin, id: id, body: body) }
    }
    private func considerNavigation() {
        // v29: observe in background too — clear/refresh decisions must keep flowing while locked.
        // Only a *new* start is gated by navigation.canPresent() (foreground, no modal).
        guard !demo else { return }
        do {
            var event: Object
            let vin: String
            if !link.authentic {
                guard let snapshot = fleet.vehicleSnapshot, snapshot.vin == fleet.selectedVin else { return }
                event = snapshot.navigationEvent(); vin = snapshot.vin
            } else {
                event = try runtime.call("embeddedDestination", [:]) as? Object ?? [:]
                vin = settings.string("vin")
                if let snapshot = fleet.vehicleSnapshot, snapshot.vin == vin {
                    let fallback = snapshot.navigationEvent()
                    if event.string("type") == "wait" || (fallback.number("at") ?? 0) > (event.number("at") ?? 0) {
                        if fallback.string("type") != "wait" { event = fallback }
                    }
                }
            }
            // v39: with hand-off enabled the destination goes to Naver Map instead of the built-in guidance,
            // so its licensed voice does the talking. One hand-off per destination, foreground only.
            if link.authentic, UserDefaults.standard.bool(forKey: "handOffToNaver"), event.string("type") == "route" {
                let token = event.string("token")
                if !token.isEmpty, token != handedOffRoute, UIApplication.shared.applicationState == .active {
                    handedOffRoute = token
                    openInNaverMap()
                }
                return
            }
            navigation.observe(event, vin: vin)
        } catch { errorMessage = error.localizedDescription }
    }
    func mergeHistory(_ url: URL) {
        guard !demo, !recoveryLock else { errorMessage = "예시·자료 복구 중에는 가져올 수 없음"; return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 100_000_000 else { throw LocalError.message("자료 크기 오류") }
            let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? Object ?? [:]
            guard root.string("kind") == "YLCompanionBackup", root.number("schema") == 1 else { throw LocalError.message("YL Companion JSON 백업만 지원함. Tesla·다른 앱의 내보내기 자료는 형식 확인 후 변환 필요.") }
            let counts = try runtime.call("mergeHistory", root.object("state")) as? Object ?? [:]
            try persist(); refresh()
            let reference = root.object("vehicleReference")
            let vin = root.object("state").object("settings").string("vin")
            if !vin.isEmpty, reference.string("vin") == vin {
                var checked: Object = [:]
                for key in ["odometerKm", "nominalAh", "nominalVoltage", "nominalKWh", "basicWarrantyKm", "batteryWarrantyKm"] {
                    if let value = reference.number(key), value.isFinite, value >= 0 { checked[key] = value }
                }
                for key in ["vin", "sourceDate", "source", "cellMaker", "cellShape", "chemistry", "basicWarrantyEnd", "batteryWarrantyEnd"] {
                    let text = reference.string(key)
                    if !text.isEmpty, text.count <= 200 { checked[key] = text }
                }
                UserDefaults.standard.set(checked, forKey: "vehicle.reference." + vin)
                objectWillChange.send()
            }
            errorMessage = "과거 운행 \(Int(counts.number("trips") ?? 0))건 · 충전 \(Int(counts.number("charges") ?? 0))건 추가 · 중복 \(Int(counts.number("duplicates") ?? 0))건 제외"
        } catch { errorMessage = error.localizedDescription }
    }
    func scheduleReminder(hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error { DispatchQueue.main.async { self?.errorMessage = error.localizedDescription }; return }
            guard granted else { DispatchQueue.main.async { self?.errorMessage = "알림 권한이 필요함" }; return }
            let content = UNMutableNotificationContent(); content.title = "출발 전 차량 확인"; content.body = "앱에서 최신 상태와 오늘의 운행 계획을 확인할 시간임. 차량 상태는 연결 후 갱신됨."; content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
            center.add(UNNotificationRequest(identifier: "YL.dailyBrief", content: content, trigger: trigger)) { error in
                DispatchQueue.main.async { self?.errorMessage = error?.localizedDescription ?? "매일 \(hour):\(String(format: "%02d", minute)) 확인 알림 설정됨. 실시간 상태 알림은 아님." }
            }
        }
    }
    func removeReminder() { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["YL.dailyBrief"]); errorMessage = "출발 확인 알림 해제됨" }
    func attachmentURL(_ name: String) -> URL? {
        guard name.range(of: "^[A-Za-z0-9-]+\\.(jpg|png)$", options: .regularExpression) != nil else { return nil }
        return folder.appendingPathComponent(name)
    }
    func storePhoto(_ data: Data) throws -> String {
        guard !demo, !recoveryLock else { throw LocalError.message("예시 모드·기록 복구 중에는 사진을 저장하지 않음") }
        guard data.count <= 15_000_000, let image = UIImage(data: data), let encoded = image.jpegData(compressionQuality: 0.82) else { throw LocalError.message("사진 형식 또는 크기 확인 필요") }
        let name = UUID().uuidString + ".jpg"
        try encoded.write(to: attachmentURL(name)!, options: [.atomic, .completeFileProtection]); return name
    }
    func resetReceipt() { receiptRequest = UUID(); receiptText = ""; receiptDraft = [:]; ocrBusy = false }
    func recognize(_ data: Data) {
        guard data.count <= 15_000_000, let uiImage = UIImage(data: data), let cgImage = uiImage.cgImage else { errorMessage = "지원 이미지·크기 확인 필요"; return }
        ocrBusy = true; receiptRequest = UUID(); let requestID = receiptRequest
        let orientation: CGImagePropertyOrientation
        switch uiImage.imageOrientation { case .up: orientation = .up; case .down: orientation = .down; case .left: orientation = .left; case .right: orientation = .right; case .upMirrored: orientation = .upMirrored; case .downMirrored: orientation = .downMirrored; case .leftMirrored: orientation = .leftMirrored; case .rightMirrored: orientation = .rightMirrored; @unknown default: orientation = .up }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
                let supported = try request.supportedRecognitionLanguages(); request.recognitionLanguages = ["ko-KR", "en-US"].filter { supported.contains($0) }
                try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
                let text = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
                DispatchQueue.main.async {
                    guard let self, self.receiptRequest == requestID else { return }; self.ocrBusy = false; self.receiptText = text
                    do { self.receiptDraft = try self.runtime.call("receipt", ["text": text]) as? Object ?? [:] }
                    catch { self.errorMessage = error.localizedDescription }
                }
            } catch { DispatchQueue.main.async { guard let self, self.receiptRequest == requestID else { return }; self.ocrBusy = false; self.errorMessage = error.localizedDescription } }
        }
    }
    func exportBackup() {
        guard !recoveryLock else { errorMessage = "원본 기록 보호 중. 빈 자료로 백업하지 않음. 정상 백업 복원 필요."; return }
        guard !demo else { errorMessage = "예시 자료는 백업하지 않음"; return }
        do {
            var attachments: [String: String] = [:]
            for row in state.rows("parkingNotes") {
                let name = row.string("photoName"); if name.isEmpty { continue }
                guard let url = attachmentURL(name) else { throw LocalError.message("사진 경로 오류") }
                attachments[name] = try Data(contentsOf: url).base64EncodedString()
            }
            let data = Data(try encodeJSON(["kind": "YLCompanionBackup", "schema": 1, "state": runtime.call("export"), "attachments": attachments]).utf8)
            guard data.count <= 100_000_000 else { throw LocalError.message("백업이 100 MB를 초과함") }
            sharedFile = try exportFile(data, stem: "Backup-테슬라 개인기록", ext: "json")
        } catch { errorMessage = error.localizedDescription }
    }
    func exportCSV() {
        guard !recoveryLock else { errorMessage = "원본 기록 보호 중. 정상 백업 복원 필요."; return }
        guard !demo else { errorMessage = "예시 자료는 내보내지 않음"; return }
        do { let content = try runtime.call("csv") as? String ?? ""; sharedFile = try exportFile(Data(content.utf8), stem: "Dataset-테슬라 운행충전", ext: "csv") }
        catch { errorMessage = error.localizedDescription }
    }
    private func exportFile(_ data: Data, stem: String, ext: String) throws -> URL {
        let exportFolder = folder.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        var version = 1; var url: URL
        repeat { url = exportFolder.appendingPathComponent("\(stem) v\(String(format: "%02d", version)).\(ext)"); version += 1 } while FileManager.default.fileExists(atPath: url.path)
        try data.write(to: url, options: [.atomic, .completeFileProtection]); return url
    }
    func restore(_ url: URL) {
        guard !demo else { errorMessage = "예시 모드를 종료해야 복원 가능함"; return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 100_000_000 else { throw LocalError.message("백업 크기 오류") }
            let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? Object ?? [:]
            guard root.string("kind") == "YLCompanionBackup", root.number("schema") == 1 else { throw LocalError.message("YL Companion 백업 파일이 아님") }
            var cleaned = try runtime.call("validate", root.object("state")) as? Object ?? [:]
            let wasLocked = recoveryLock
            let photos = root.object("attachments"); var remap: [String: String] = [:]
            for row in cleaned.rows("parkingNotes") {
                let name = row.string("photoName"); if name.isEmpty || remap[name] != nil { continue }
                guard attachmentURL(name) != nil, let raw = photos[name] as? String, let data = Data(base64Encoded: raw) else { throw LocalError.message("사진이 누락되거나 손상됨") }
                guard data.count <= 15_000_000, let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.82) else { throw LocalError.message("백업 사진 형식 오류") }
                let newName = UUID().uuidString + ".jpg"
                try jpeg.write(to: attachmentURL(newName)!, options: [.atomic, .completeFileProtection]); remap[name] = newName
            }
            cleaned["parkingNotes"] = cleaned.rows("parkingNotes").map { row -> Object in var row = row; if let name = remap[row.string("photoName")] { row["photoName"] = name }; return row }
            let old = try runtime.call("export")
            navigation.reset(); link.disconnect()
            if wasLocked, FileManager.default.fileExists(atPath: recordFile.path) { try FileManager.default.copyItem(at: recordFile, to: folder.appendingPathComponent("recovery-\(UUID().uuidString).json")) }
            do { _ = try runtime.call("load", cleaned); recoveryLock = false; try persist(); refresh(); errorMessage = "복원 완료. 차량 키는 별도 등록·확인 필요."; resume() }
            catch { recoveryLock = wasLocked; _ = try? runtime.call("load", old); refresh(); throw error }
        } catch { errorMessage = error.localizedDescription }
    }
    func fetchWeather() {
        if let previous = state.object("weather").number("receivedAt"), Date().timeIntervalSince1970*1000-previous < 600000 { errorMessage = "10분 이내 조회한 날씨를 사용함"; return }
        let loc = groups.object("location")
        guard !demo, output.object("fresh").flag("location"), let lat = loc.number("latitude"), let lng = loc.number("longitude") else { errorMessage = "최신 차량 위치 수신 후 조회 가능함"; return }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [URLQueryItem(name: "latitude", value: String(lat)), URLQueryItem(name: "longitude", value: String(lng)), URLQueryItem(name: "current", value: "temperature_2m,precipitation,weather_code"), URLQueryItem(name: "timezone", value: "Asia/Seoul")]
        guard let url = components.url else { return }
        var request = URLRequest(url: url); request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard error == nil, let http = response as? HTTPURLResponse, http.statusCode == 200, let data, data.count < 100000, let result = try? JSONSerialization.jsonObject(with: data) as? Object else { self.errorMessage = "날씨 조회 실패. 저장된 차량 데이터는 유지됨."; return }
                var current = result.object("current"); current["receivedAt"] = Date().timeIntervalSince1970 * 1000
                self.mutate("weather", current)
            }
        }.resume()
    }
}
