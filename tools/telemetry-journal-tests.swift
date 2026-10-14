import Foundation
@main struct TelemetryJournalTests {
    static func main() async throws {
        let root = URL(fileURLWithPath: "Xcode/TelemetryJournalTest-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("raw.json")
        func row(_ i: Int, _ value: Double? = nil) -> FleetTelemetryReading {
            FleetTelemetryReading(vin: "TESTVIN00000000001", field: "Soc", at: Date(timeIntervalSince1970: Double(i)), number: value ?? Double(i % 100), text: "", invalid: false)
        }
        let initial = (0..<5000).map { row($0) }
        let baseline = try JSONEncoder().encode(initial); try baseline.write(to: file)
        let restored = try FleetTelemetryJournal.restore(file)
        let writer = FleetTelemetryJournal(file: file, restored: restored)
        async let one = writer.ingest([row(5001)])
        async let two = writer.ingest([row(5002)])
        _ = try await (one,two)
        let unchanged = try Data(contentsOf: file)
        precondition(unchanged == baseline, "Small deltas must not rewrite the large checkpoint")
        let journal = file.appendingPathExtension("journal")
        let deltaBytes = try Data(contentsOf: journal).count
        precondition(deltaBytes < baseline.count / 100)
        let duplicate = try await writer.ingest([row(5001)])
        precondition(duplicate.changed == 0)
        let corrected = try await writer.ingest([row(5001,42)])
        precondition(corrected.changed == 1)
        let restart = try FleetTelemetryJournal.restore(file)
        precondition(restart.records.count == 5002, "Concurrent imports must preserve both batches")
        precondition(restart.records.first(where: { $0.id == row(5001).id })?.number == 42)
        let handle = try FileHandle(forWritingTo: journal); try handle.seekToEnd(); try handle.write(contentsOf: Data("[partial".utf8)); try handle.close()
        let partial = try FleetTelemetryJournal.restore(file)
        precondition(partial.records.count == 5002 && partial.validJournalBytes < partial.journalBytes)
        let repaired = FleetTelemetryJournal(file: file, restored: partial, checkpointBytes: 1)
        _ = try await repaired.ingest([row(5003)])
        let final = try FleetTelemetryJournal.restore(file)
        precondition(final.records.count == 5003 && final.journalBytes == 0)
        print("PASS: durable telemetry deltas, concurrent merge, duplicate/correction replay, partial-tail recovery and atomic checkpoint")
    }
}
