import Foundation

@main struct RecordRecoveryTests {
    static func main() throws {
        let files = FileManager.default
        let root = URL(fileURLWithPath: files.currentDirectoryPath).appendingPathComponent("Xcode/BuildOutput/RecoveryTest-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let source = root.appendingPathComponent("records.json"), snapshot = root.appendingPathComponent("snapshot.json")
        let original = Data([0, 255, 123, 34, 97, 34, 58]) // Deliberately not valid JSON/UTF-8.
        try original.write(to: source)
        try RecordRecoverySafety.preserve(source: source, snapshot: snapshot)
        let sourceBytes = try Data(contentsOf: source), snapshotBytes = try Data(contentsOf: snapshot)
        precondition(sourceBytes == original)
        precondition(snapshotBytes == original)
        try Data("later valid record".utf8).write(to: source)
        try RecordRecoverySafety.preserve(source: source, snapshot: snapshot)
        let retained = try Data(contentsOf: snapshot)
        precondition(retained == original, "Existing evidence must not be overwritten")
        let missing = root.appendingPathComponent("missing.json"), failed = root.appendingPathComponent("must-not-exist.json")
        do { try RecordRecoverySafety.preserve(source: missing, snapshot: failed); preconditionFailure("Missing original must fail closed") }
        catch { precondition(!files.fileExists(atPath: failed.path)) }
        let names = try files.contentsOfDirectory(atPath: root.path)
        precondition(names.allSatisfy { !$0.hasSuffix(".partial") })
        print("PASS: recovery preserves exact unreadable bytes, refuses snapshot replacement and fails closed without partial files")
    }
}
