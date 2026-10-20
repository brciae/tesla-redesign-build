import Foundation
import CryptoKit

/// Disposable synthesized audio only. Never traverses outside this cache or follows links.
enum VoiceDiskCache {
    static let lock = NSRecursiveLock()
    static let byteLimit = 256 * 1_048_576
    static let fileLimit = 2_000
    static func phrase(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    static func key(text: String, voice: String) -> String {
        SHA256.hash(data: Data("\(voice)_\(phrase(text))".utf8)).map { String(format: "%02x", $0) }.joined()
    }
    struct Entry {
        let url: URL
        let bytes: Int
        let date: Date
    }
    static func files(_ root: URL) -> [Entry] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var result: [Entry] = []
        for case let url as URL in iterator {
            guard let v = try? url.resourceValues(forKeys: keys) else { continue }
            if v.isSymbolicLink == true { iterator.skipDescendants(); continue }
            guard v.isRegularFile == true, url.pathExtension == "wav" else { continue }
            result.append(Entry(url: url, bytes: v.fileSize ?? 0, date: v.contentModificationDate ?? .distantPast))
        }
        return result
    }
    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("txt"))
    }
    static func maintain(_ root: URL, byteLimit: Int = VoiceDiskCache.byteLimit, fileLimit: Int = VoiceDiskCache.fileLimit) -> [Entry] {
        var groups: [String: [Entry]] = [:]
        for entry in files(root) {
            let folder = entry.url.deletingLastPathComponent()
            // Shared legacy files without an attributable voice stay distinct.
            guard folder.lastPathComponent.hasPrefix("v_"), entry.bytes > 100, entry.bytes <= 32_000_000,
                  let text = try? String(contentsOf: entry.url.deletingPathExtension().appendingPathExtension("txt"), encoding: .utf8),
                  !phrase(text).isEmpty else { continue }
            groups[folder.path + "\n" + phrase(text), default: []].append(entry)
        }
        for entries in groups.values {
            lock.lock()
            defer { lock.unlock() }
            guard entries.allSatisfy({ (try? $0.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) == $0.date }) else { continue }
            let ordered = entries.sorted { $0.date == $1.date ? $0.url.path < $1.url.path : $0.date > $1.date }
            guard let newest = ordered.first,
                  let text = try? String(contentsOf: newest.url.deletingPathExtension().appendingPathExtension("txt"), encoding: .utf8) else { continue }
            let folder = newest.url.deletingLastPathComponent()
            let canonical = folder.appendingPathComponent(key(text: text, voice: String(folder.lastPathComponent.dropFirst(2))) + ".wav")
            if newest.url != canonical {
                guard let data = try? Data(contentsOf: newest.url), (try? data.write(to: canonical, options: .atomic)) != nil else { continue }
                try? Data(phrase(text).utf8).write(to: canonical.deletingPathExtension().appendingPathExtension("txt"), options: .atomic)
                try? FileManager.default.setAttributes([.modificationDate: newest.date], ofItemAtPath: canonical.path)
            }
            // Keep the newest bytes under the lookup key, even when an older canonical file existed.
            for old in ordered where old.url != canonical { remove(old.url) }
        }
        var entries = files(root).sorted { $0.date == $1.date ? $0.url.path > $1.url.path : $0.date < $1.date }
        var bytes = entries.reduce(0) { $0 + $1.bytes }, count = entries.count
        var removed = Set<URL>()
        for entry in entries where bytes > byteLimit || count > fileLimit {
            lock.lock()
            defer { lock.unlock() }
            guard (try? entry.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) == entry.date else { continue }
            remove(entry.url); removed.insert(entry.url); bytes -= entry.bytes; count -= 1
        }
        entries.removeAll { removed.contains($0.url) }
        return entries
    }
}
