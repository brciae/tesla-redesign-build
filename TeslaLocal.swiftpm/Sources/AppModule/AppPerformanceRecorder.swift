import Foundation

/// Bounded local timings only: never records arguments, VINs, locations, tokens or vehicle payloads.
final class AppPerformanceRecorder: @unchecked Sendable {
    static let shared = AppPerformanceRecorder()
    private struct Stat { var count = 0; var total = 0.0; var maximum = 0.0; var slow = 0 }
    private let lock = NSLock()
    private var stats: [String: [Bool: Stat]] = [:]
    private var slowEvents: [[String: Any]] = []
    private var graphicsSuspended = false
    private struct Running { let name: String; let began: TimeInterval; let main: Bool; let graphics: Bool }
    private var running: [UUID: Running] = [:]
    private let started = Date()
    func measure<T>(_ name: String, _ operation: () throws -> T) rethrows -> T {
        let token = begin(name)
        defer { end(token) }
        return try operation()
    }
    func begin(_ name: String) -> UUID {
        let token = UUID(); lock.lock(); defer { lock.unlock() }
        if running.count < 16 { running[token] = Running(name: name, began: ProcessInfo.processInfo.systemUptime, main: Thread.isMainThread, graphics: graphicsSuspended) }
        return token
    }
    func end(_ token: UUID) {
        lock.lock(); let operation = running.removeValue(forKey: token); lock.unlock()
        if let operation { record(operation.name, seconds: ProcessInfo.processInfo.systemUptime - operation.began, main: operation.main, graphics: operation.graphics) }
    }
    func record(_ name: String, seconds: Double, main: Bool, graphics: Bool? = nil) {
        guard seconds.isFinite, seconds >= 0 else { return }
        lock.lock(); defer { lock.unlock() }
        guard stats[name] != nil || stats.count < 80 else { return }
        let mode = graphics ?? graphicsSuspended
        var modes = stats[name] ?? [:], stat = modes[mode] ?? Stat()
        stat.count += 1; stat.total += seconds; stat.maximum = max(stat.maximum, seconds)
        if seconds >= 0.05 {
            stat.slow += 1
            slowEvents.append(["operation": name, "milliseconds": seconds * 1000, "mainThread": main,
                               "secondsSinceStart": Date().timeIntervalSince(started), "suspended3D": mode])
            if slowEvents.count > 120 { slowEvents.removeFirst(slowEvents.count - 120) }
        }
        modes[mode] = stat; stats[name] = modes
    }
    func setGraphicsSuspended(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }; graphicsSuspended = value
    }
    var graphicsMode: Bool { lock.lock(); defer { lock.unlock() }; return graphicsSuspended }
    func snapshot() -> [String: Any] {
        lock.lock(); let current = stats, events = slowEvents, executing = running; lock.unlock()
        return ["schema": 1, "started": ISO8601DateFormatter().string(from: started),
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "test",
                "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "test",
                "limits": ["operationNames": 80, "modes": 2, "slowEvents": 120, "executing": 16],
                "operations": current.keys.sorted().flatMap { name -> [[String: Any]] in
                    [false, true].compactMap { mode -> [String: Any]? in
                    guard let value = current[name]?[mode] else { return nil }
                    return ["name": name, "suspended3D": mode, "count": value.count, "totalMilliseconds": value.total * 1000,
                            "maximumMilliseconds": value.maximum * 1000, "over50ms": value.slow]
                    }
                }, "slowEvents": events, "executing": executing.values.map { operation in
                    ["name": operation.name, "mainThread": operation.main, "suspended3D": operation.graphics,
                     "elapsedMilliseconds": (ProcessInfo.processInfo.systemUptime - operation.began) * 1000] as [String: Any]
                }]
    }
}

#if canImport(UIKit) && canImport(SwiftUI)
import UIKit
import SwiftUI

/// One queued main-thread probe at most. Background/suspension time never counts as a UI stall.
final class AppPerformanceWatchdog: @unchecked Sendable {
    static let shared = AppPerformanceWatchdog()
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "YLCompanion.performance", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var pending = false
    private var pendingSince: TimeInterval?
    private var pendingEpoch = 0
    private var active = false
    private var background = false
    private var epoch = 0
    private var observers: [NSObjectProtocol] = []
    private var lastWrite = Date.distantPast
    private let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("YLCompanion", isDirectory: true)
    func start() {
        guard timer == nil else { return }
        precondition(Thread.isMainThread)
        lock.lock(); active = UIApplication.shared.applicationState == .active
        background = UIApplication.shared.applicationState == .background; lock.unlock()
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification, UIApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                self.lock.lock(); self.active = note.name == UIApplication.didBecomeActiveNotification
                if note.name == UIApplication.didEnterBackgroundNotification { self.background = true }
                if note.name == UIApplication.didBecomeActiveNotification { self.background = false }
                self.epoch += 1; self.lock.unlock()
            })
        }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .milliseconds(500), leeway: .milliseconds(100))
        source.setEventHandler { [weak self] in self?.probe() }; timer = source
        queue.async { [self] in
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let old = try? Data(contentsOf: folder.appendingPathComponent("performance-current.json")), old.count < 200000 {
                try? old.write(to: folder.appendingPathComponent("performance-previous.json"), options: .atomic)
            }
            source.resume()
        }
    }
    private func report() -> [String: Any] {
        var value = AppPerformanceRecorder.shared.snapshot()
        lock.lock(); value["uiActive"] = active
        if active, pendingEpoch == epoch, let since = pendingSince {
            value["mainProbePendingMilliseconds"] = (ProcessInfo.processInfo.systemUptime - since) * 1000
        }
        lock.unlock(); return value
    }
    private func probe() {
        lock.lock(); let suspended = background; lock.unlock()
        guard !suspended else { return }
        if Date().timeIntervalSince(lastWrite) >= 10 {
            lastWrite = Date()
            if let data = try? JSONSerialization.data(withJSONObject: report(), options: [.sortedKeys]) {
                try? data.write(to: folder.appendingPathComponent("performance-current.json"), options: .atomic)
            }
        }
        lock.lock()
        guard active, !pending else { lock.unlock(); return }
        pending = true; let generation = epoch
        let start = ProcessInfo.processInfo.systemUptime; pendingSince = start; pendingEpoch = generation; lock.unlock()
        let graphics = AppPerformanceRecorder.shared.graphicsMode
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            self.lock.lock(); let valid = self.active && self.epoch == generation
            self.pending = false; self.pendingSince = nil; self.lock.unlock()
            if valid { AppPerformanceRecorder.shared.record("main.queue.wait", seconds: elapsed, main: true, graphics: graphics) }
        }
    }
    func export(context: [String: Any], completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async { [self] in
            let result = Result<URL, Error> {
                var value = report(); value["context"] = context
                if let old = try? Data(contentsOf: folder.appendingPathComponent("performance-previous.json")), old.count < 200000,
                   let previous = try? JSONSerialization.jsonObject(with: old) { value["previousSession"] = previous }
                let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted])
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let mode = context["suspended3D"] as? Bool == true ? "3D-off" : "3D-on"
                let target = folder.appendingPathComponent("YL-Companion-performance-\(mode).json")
                try data.write(to: target, options: .atomic); return target
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}

struct PerformanceDiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("diagnostics.suspend3D") private var suspend3D = false
    @State private var exporting = false
    @State private var exportURL: URL?
    var body: some View {
        Form {
            Section("렌더링 비교") {
                Toggle("차량·캐릭터 3D 일시 중지", isOn: $suspend3D).accessibilityIdentifier("performance.suspend3D")
                Text("켜고 홈·탭 이동·스크롤 속도를 비교한 뒤 다시 끄면 3D가 복구됨.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("실기기 진단 기록") {
                Text("느려지는 동작을 한 뒤 기록을 공유하면 됨. 화면 응답 지연과 작업 시간만 기록하며 차량 식별값·위치·인증 정보는 포함하지 않음.").font(.footnote)
                Button("진단 기록 공유") { export() }.disabled(exporting).accessibilityIdentifier("performance.export")
            }
        }.navigationTitle("성능 진단")
            .onChange(of: suspend3D) { _, value in AppPerformanceRecorder.shared.setGraphicsSuspended(value) }
            .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
                if let exportURL { PerformanceShare(url: exportURL).accessibilityIdentifier("performance.share") }
            }
    }
    @MainActor private func export() {
        exporting = true
        let context: [String: Any] = ["device": UIDevice.current.model, "iOS": UIDevice.current.systemVersion,
            "thermalState": ProcessInfo.processInfo.thermalState.rawValue, "lowPower": ProcessInfo.processInfo.isLowPowerModeEnabled,
            "suspended3D": suspend3D, "archiveRecords": FleetTelemetryStore.shared.records.count,
            "tripRecords": model.state.rows("trips").count, "chargeRecords": model.state.rows("charges").count]
        AppPerformanceWatchdog.shared.export(context: context) { result in
            exporting = false
            switch result { case .success(let url): exportURL = url
            case .failure(let error): model.errorMessage = error.localizedDescription }
        }
    }
}

private struct PerformanceShare: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.view.accessibilityIdentifier = "performance.share"
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
