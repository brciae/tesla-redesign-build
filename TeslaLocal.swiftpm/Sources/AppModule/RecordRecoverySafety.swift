import Foundation

enum RecordRecoverySafety {
    // Commit a complete byte copy, never a partially written snapshot. Existing
    // recovery evidence is immutable even if the live database changes later.
    static func preserve(source: URL, snapshot: URL) throws {
        let files = FileManager.default
        guard !files.fileExists(atPath: snapshot.path) else { return }
        let pending = snapshot.deletingLastPathComponent().appendingPathComponent("recovery-\(UUID().uuidString).partial")
        do {
            try files.copyItem(at: source, to: pending)
            try files.moveItem(at: pending, to: snapshot)
        } catch {
            try? files.removeItem(at: pending)
            throw error
        }
    }
}
