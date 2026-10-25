import Foundation

@main struct VoiceCacheTests {
    static func main() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: "Xcode/BuildOutput/VoiceCacheTest-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func write(_ voice: String, _ name: String, _ text: String, _ value: UInt8, _ at: Double) throws -> URL {
            let dir = root.appendingPathComponent("v_" + voice)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(name + ".wav")
            try Data(repeating: value, count: 300).write(to: url)
            try Data(text.utf8).write(to: url.deletingPathExtension().appendingPathExtension("txt"))
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: at)], ofItemAtPath: url.path)
            return url
        }
        let canonical = VoiceDiskCache.key(text: "앞에서 우회전", voice: "voiceA")
        _ = try write("voiceA", canonical, "앞에서 우회전", 1, 10)
        let alias = try write("voiceA", "oldAliasHash", " 앞에서   우회전\n", 2, 20)
        let other = try write("voiceB", VoiceDiskCache.key(text: "앞에서 우회전", voice: "voiceB"), "앞에서 우회전", 3, 15)
        let entries = VoiceDiskCache.maintain(root)
        precondition(entries.count == 2, "Same voice/normalized phrase collapses; different voice survives")
        precondition(!fm.fileExists(atPath: alias.path))
        let latest = root.appendingPathComponent("v_voiceA/" + canonical + ".wav")
        let newestBytes = try Data(contentsOf: latest)
        precondition(newestBytes == Data(repeating: 2, count: 300), "Newest alias bytes replace older canonical bytes")
        precondition(fm.fileExists(atPath: other.path))
        precondition(VoiceDiskCache.maintain(root).count == 2, "Idempotent migration")
        let limited = VoiceDiskCache.maintain(root, byteLimit: 300, fileLimit: 1)
        precondition(limited.count == 1, "Exactly one recording remains under the byte/count budget")
        precondition(limited[0].url.standardizedFileURL.path == latest.standardizedFileURL.path, "Newest canonical path remains under budget")
        precondition(!fm.fileExists(atPath: other.deletingPathExtension().appendingPathExtension("txt").path))
        // A symlink in the cache must not expose another folder to cleanup.
        let outside = root.deletingLastPathComponent().appendingPathComponent("VoiceCacheOutside-" + UUID().uuidString)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outside) }
        let protected = outside.appendingPathComponent("keep.wav")
        try Data(repeating: 4, count: 300).write(to: protected)
        try fm.createSymbolicLink(at: root.appendingPathComponent("v_link"), withDestinationURL: outside)
        _ = VoiceDiskCache.maintain(root, byteLimit: 0, fileLimit: 0)
        precondition(fm.fileExists(atPath: protected.path), "Never follows cache symlinks")
        print("PASS: latest same-voice phrase retained, canonical lookup preserved, voices isolated, idempotence, byte/count caps, sidecar cleanup and symlink containment")
    }
}
