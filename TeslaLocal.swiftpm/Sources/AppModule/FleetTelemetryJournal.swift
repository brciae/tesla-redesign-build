import Foundation

/// Serialized, durable deltas keep each NAS page from rewriting all 50,000 retained samples.
actor FleetTelemetryJournal {
    struct Restored: Sendable { let records: [FleetTelemetryReading]; let journalBytes: Int; let validJournalBytes: Int }
    struct Update: Sendable { let records: [FleetTelemetryReading]; let changed: Int; let revision: UInt64; let warning: String? }
    private let file: URL
    private let journal: URL
    private let checkpointBytes: Int
    private var records: [FleetTelemetryReading]
    private var journalBytes: Int
    private var validJournalBytes: Int
    private var revision: UInt64 = 0
    static func restore(_ file: URL) throws -> Restored {
        let manager = FileManager.default
        let base = manager.fileExists(atPath: file.path) ? try JSONDecoder().decode([FleetTelemetryReading].self, from: Data(contentsOf: file)) : []
        let journal = file.appendingPathExtension("journal")
        guard manager.fileExists(atPath: journal.path) else { return Restored(records: base, journalBytes: 0, validJournalBytes: 0) }
        let bytes = try Data(contentsOf: journal)
        guard bytes.count <= 10_000_000 else { throw FleetTelemetryData.failure("Telemetry 변경 기록 복구 필요. 원본 보존 중.") }
        let valid = bytes.lastIndex(of: 10).map { $0 + 1 } ?? 0
        var changes: [FleetTelemetryReading] = []
        // An interrupted final append is uncommitted; malformed complete lines protect the entire original.
        for line in bytes.prefix(valid).split(separator: 10) { changes += try JSONDecoder().decode([FleetTelemetryReading].self, from: Data(line)) }
        return Restored(records: FleetTelemetryData.merge(base, changes), journalBytes: bytes.count, validJournalBytes: valid)
    }
    init(file: URL, restored: Restored, checkpointBytes: Int = 2_000_000) {
        self.file = file; self.journal = file.appendingPathExtension("journal")
        self.records = restored.records; self.journalBytes = restored.journalBytes
        self.validJournalBytes = restored.validJournalBytes; self.checkpointBytes = max(1, checkpointBytes)
    }
    func ingest(_ incoming: [FleetTelemetryReading]) throws -> Update {
        let old = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let changed = incoming.filter { row in
            guard let previous = old[row.id] else { return true }
            return previous.number != row.number || previous.text != row.text || previous.invalid != row.invalid
        }
        guard !changed.isEmpty else { return Update(records: records, changed: 0, revision: revision, warning: nil) }
        var delta = try JSONEncoder().encode(changed); delta.append(10)
        if validJournalBytes + delta.count > 10_000_000 { try checkpoint(records) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: journal.path) {
            #if os(iOS)
            let attributes: [FileAttributeKey: Any]? = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            #else
            let attributes: [FileAttributeKey: Any]? = nil
            #endif
            guard FileManager.default.createFile(atPath: journal.path, contents: nil, attributes: attributes) else { throw FleetTelemetryData.failure("Telemetry 변경 기록 생성 실패") }
        }
        let handle = try FileHandle(forWritingTo: journal); defer { try? handle.close() }
        if journalBytes != validJournalBytes { try handle.truncate(atOffset: UInt64(validJournalBytes)) }
        try handle.seekToEnd()
        do { try handle.write(contentsOf: delta); try handle.synchronize() }
        catch { journalBytes = Int((try? handle.seekToEnd()) ?? UInt64(validJournalBytes)); throw error }
        validJournalBytes += delta.count; journalBytes = validJournalBytes
        records = FleetTelemetryData.merge(records, changed); revision &+= 1
        var warning: String?
        if journalBytes >= checkpointBytes {
            do { try checkpoint(records) }
            catch { warning = "전체 파일 정리 재시도 대기 · 변경 기록은 저장됨" }
        }
        return Update(records: records, changed: changed.count, revision: revision, warning: warning)
    }
    private func checkpoint(_ values: [FleetTelemetryReading]) throws {
        let encoded = try JSONEncoder().encode(values)
        #if os(iOS)
        try encoded.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try encoded.write(to: file, options: .atomic)
        #endif
        // A crash before truncation replays duplicate IDs safely against the new checkpoint.
        let handle = try FileHandle(forWritingTo: journal); defer { try? handle.close() }
        try handle.truncate(atOffset: 0); try handle.synchronize(); journalBytes = 0; validJournalBytes = 0
    }
}
