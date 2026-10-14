import Foundation
@main struct AttachmentSafetyTests {
    static func main() throws {
        precondition(AttachmentSafety.base64Budget(bytes: 15_000_000) == 20_000_000)
        precondition(AttachmentSafety.base64Budget(bytes: Int.max) == nil)
        precondition(AttachmentSafety.base64Budget(bytes: -1) == nil)
        precondition(AttachmentSafety.base64Budget(bytes: 1) == 4)
        precondition(AttachmentSafety.dimensionsAllowed(width: 8000, height: 6000))
        precondition(!AttachmentSafety.dimensionsAllowed(width: 100000, height: 100000))
        precondition(!AttachmentSafety.dimensionsAllowed(width: .nan, height: 100))
        precondition(!AttachmentSafety.dimensionsAllowed(width: .infinity, height: 100))
        let root = URL(fileURLWithPath: "Xcode/AttachmentSafetyTest-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let photo = root.appendingPathComponent("photo.jpg"), backup = root.appendingPathComponent("backup.json")
        let raw = Data([255, 255, 255, 0, 1]); try raw.write(to: photo)
        try AttachmentSafety.writeBackup(state: Data(#"{"schema":1,"trips":[]}"#.utf8), photos: ["photo.jpg": photo], destination: backup)
        let restored = try JSONSerialization.jsonObject(with: Data(contentsOf: backup)) as! [String: Any]
        precondition(restored["kind"] as? String == "YLCompanionBackup")
        precondition(Data(base64Encoded: (restored["attachments"] as! [String: String])["photo.jpg"]!) == raw)
        precondition(!FileManager.default.fileExists(atPath: backup.appendingPathExtension("partial").path))
        let large = root.appendingPathComponent("large.jpg"); FileManager.default.createFile(atPath: large.path, contents: nil)
        let handle = try FileHandle(forWritingTo: large); try handle.truncate(atOffset: UInt64(AttachmentSafety.maximumPhotoBytes + 1)); try handle.close()
        let rejected = root.appendingPathComponent("rejected.json")
        do { try AttachmentSafety.writeBackup(state: Data("{}".utf8), photos: ["large.jpg": large], destination: rejected); preconditionFailure("Oversized photo must be rejected") } catch { }
        precondition(!FileManager.default.fileExists(atPath: rejected.path), "Reject before creating export")
        print("PASS: streaming backup JSON/base64 roundtrip and oversized photo pre-allocation rejection")
        print("PASS: attachment encoded-size preflight, integer overflow rejection and decompressed pixel limits")
    }
}
