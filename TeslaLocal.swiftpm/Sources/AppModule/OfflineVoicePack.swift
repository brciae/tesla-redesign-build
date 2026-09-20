import SwiftUI
import CryptoKit

enum VoiceFileIntegrity {
    static func verify(_ url: URL, file: VoicePackManifest.File) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard Int64(values.fileSize ?? -1) == file.bytes else { throw NSError(domain: "VoicePack", code: 1) }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024*1024), !data.isEmpty { hash.update(data: data) }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == file.sha256 else { throw NSError(domain: "VoicePack", code: 2) }
    }
}

private final class VoiceDownloadProgress: NSObject, URLSessionDownloadDelegate {
    let update: (Int64) -> Void
    init(update: @escaping (Int64) -> Void) { self.update = update }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) { update(totalBytesWritten) }
}

@MainActor
final class OfflineVoicePack: ObservableObject {
    static let shared = OfflineVoicePack()
    nonisolated static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("YLCompanion/VoicePack/" + VoicePackManifest.revision, isDirectory: true)
    }
    @Published private(set) var ready = false
    @Published private(set) var downloading = false
    @Published private(set) var progress = 0.0
    @Published private(set) var status = "음성팩 미설치"
    private var task: Task<Void, Never>?
    private var generation = UUID()
    init() {
        let root = Self.directory
        ready = FileManager.default.fileExists(atPath: root.appendingPathComponent("verified").path) && VoicePackManifest.files.allSatisfy { file in
            (try? root.appendingPathComponent(file.path).resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) == file.bytes } ?? false
        }
        if ready { status = "AI 음성 준비됨 · 기본 10종 + 프리셋 10종"; progress = 1 }
    }
    func download() {
        guard !downloading, !ready else { return }
        let id = UUID(); generation = id; downloading = true; status = "Wi-Fi 다운로드 준비"; progress = 0
        task = Task {
            let config = URLSessionConfiguration.default
            config.allowsCellularAccess = false; config.allowsExpensiveNetworkAccess = false
            config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 1800
            let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
            do {
                let root = Self.directory
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                var rootForValues = root; var values = URLResourceValues(); values.isExcludedFromBackup = true; try rootForValues.setResourceValues(values)
                var completed: Int64 = 0
                for file in VoicePackManifest.files {
                    try Task.checkCancellation()
                    let destination = root.appendingPathComponent(file.path)
                    let valid = await Task.detached { (try? VoiceFileIntegrity.verify(destination, file: file)) != nil }.value
                    try Task.checkCancellation()
                    guard generation == id else { return }
                    if !valid {
                        status = "음성팩 다운로드 중"
                        let prior = completed
                        let delegate = VoiceDownloadProgress { [weak self] bytes in Task { @MainActor in
                            guard let self, self.generation == id else { return }
                            self.progress = Double(prior + min(file.bytes, bytes))/Double(VoicePackManifest.bytes)
                        } }
                        let (temp, response) = try await session.download(from: URL(string: VoicePackManifest.base + file.path)!, delegate: delegate)
                        defer { try? FileManager.default.removeItem(at: temp) }
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NSError(domain: "VoicePack", code: 3) }
                        status = "다운로드 무결성 확인"
                        try await Task.detached { try VoiceFileIntegrity.verify(temp, file: file) }.value
                        try Task.checkCancellation()
                        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                        try FileManager.default.moveItem(at: temp, to: destination)
                    }
                    completed += file.bytes; progress = Double(completed)/Double(VoicePackManifest.bytes)
                }
                try Task.checkCancellation()
                try Data(VoicePackManifest.revision.utf8).write(to: Self.directory.appendingPathComponent("verified"), options: .atomic)
                guard generation == id else { return }
                ready = true; downloading = false; status = "AI 음성 준비됨 · 기본 10종 + 프리셋 10종"
            } catch {
                guard generation == id else { return }
                downloading = false; status = Task.isCancelled ? "중단됨 · 받은 파일은 재사용함" : "다운로드 실패 · Wi-Fi 확인 후 재시도 가능"
            }
        }
    }
    func cancel() { generation = UUID(); task?.cancel(); task = nil; downloading = false; status = "중단됨 · 받은 파일은 재사용함" }
    func repair() { guard !downloading else { return }; ready = false; download() }
}

struct OfflineVoicePackSection: View {
    var body: some View { Section("무료 오프라인 음성팩") { OfflineVoicePackRow() } }
}

/// v31: one row plus an ⓘ popover instead of a paragraph of licence and capability text.
struct OfflineVoicePackRow: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var pack = OfflineVoicePack.shared
    var body: some View {
        HStack {
            Text("앱 내장 음성")
            Spacer(minLength: 4)
            Text(pack.ready ? "사용 중" : pack.downloading ? "받는 중" : "미설치").foregroundStyle(Theme.muted)
            InfoNote("앱 내장 음성", "네트워크 없이 기기 안에서 합성하는 음성임. Wi-Fi와 저장 공간 약 \(Int(ceil(Double(VoicePackManifest.bytes)/1_000_000))) MB가 필요하고, PC·API 키·유료 구독은 필요하지 않음. Supertonic 3 · 모델 OpenRAIL-M, 코드 MIT. 실제 인물의 목소리를 복제한 것이 아님. 현재 상태: \(pack.status)")
        }
        if pack.downloading { ProgressView(value: pack.progress); Button("다운로드 중단") { pack.cancel() } }
        else if !pack.ready { Button("Wi-Fi로 음성팩 받기 · \(Int(ceil(Double(VoicePackManifest.bytes)/1_000_000))) MB") { pack.download() } }
        else { Button("음성팩 검사·복구") { model.voice.stop(); pack.repair() } }
    }
}
