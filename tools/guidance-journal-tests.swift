import Foundation
@main struct GuidanceJournalTests {
    static func main() throws {
        let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Xcode/GuidanceJournalTest-" + UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: path) }
        let journal = GuidanceJournal(file: path), now = Date()
        journal.append(vin: "A", text: "전방 안내", navigation: true, now: now)
        journal.append(vin: "B", text: "다른 차량", navigation: false, now: now)
        journal.waitForPendingWrites()
        let firstSize = try path.resourceValues(forKeys: [.fileSizeKey]).fileSize!
        precondition(firstSize < 1024)
        var restored = GuidanceJournal(file: path)
        precondition(restored.rows(vin: "A", from: now.addingTimeInterval(-1), to: now.addingTimeInterval(1)).count == 1)
        let handle = try FileHandle(forWritingTo: path); try handle.seekToEnd(); try handle.write(contentsOf: Data("{\"partial\":".utf8)); try handle.close()
        restored = GuidanceJournal(file: path)
        restored.waitForPendingWrites()
        restored.append(vin: "A", text: "복구 후 안내", navigation: true, now: now.addingTimeInterval(2))
        restored.waitForPendingWrites()
        precondition(GuidanceJournal(file: path).records.count == 3)
        for i in 0..<500 { restored.append(vin: "A", text: String(repeating: "가", count: 1600), navigation: true, now: now.addingTimeInterval(Double(i))) }
        restored.waitForPendingWrites()
        precondition(restored.records.count < 500, "Byte budget must bound long messages, not just item count")
        let diskBytes = try path.resourceValues(forKeys: [.fileSizeKey]).fileSize!
        precondition(diskBytes < 2097152)
        let bounded = GuidanceJournal(file: path)
        precondition(!bounded.records.isEmpty && bounded.records.count <= 2000)
        print("PASS: spoken guidance append/reload, VIN isolation, partial-tail recovery and bounded long-message retention")
    }
}
