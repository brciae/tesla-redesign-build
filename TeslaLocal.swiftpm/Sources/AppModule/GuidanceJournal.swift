import Foundation
import Combine

struct SpokenGuidance: Codable, Identifiable {
    var id = UUID().uuidString
    var at: Date
    var vin: String
    var text: String
    var navigation: Bool
}
/// Append only on confirmed playback start. Small serial writes avoid rewriting history for every cue.
final class GuidanceJournal: ObservableObject {
    static let shared = GuidanceJournal()
    @Published private(set) var records: [SpokenGuidance] = []
    private let writer = DispatchQueue(label: "YL.guidance.journal", qos: .utility)
    private let file: URL
    private var byteSizes: [Int] = []
    init(file override: URL? = nil) {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("YLCompanion")
        file = override ?? folder.appendingPathComponent("spoken-guidance.jsonl")
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let bytes = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, bytes <= 2097152,
           let data = try? Data(contentsOf: file) {
            records = Array(data.split(separator: 10).compactMap { try? JSONDecoder().decode(SpokenGuidance.self, from: Data($0)) }.suffix(2000))
            byteSizes = records.map { ((try? JSONEncoder().encode($0).count) ?? 0) + 1 }
            trimToBudget()
            if data.last != 10 || data.count > 1048576 {
                let retained = records, destination = file
                writer.async {
                    var checkpoint = Data()
                    for row in retained { if let encoded = try? JSONEncoder().encode(row) { checkpoint.append(encoded); checkpoint.append(10) } }
                    try? checkpoint.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                }
            }
        }
    }
    func append(vin: String, text: String, navigation: Bool, now: Date = Date()) {
        guard !vin.isEmpty, !text.isEmpty else { return }
        let row = SpokenGuidance(at: now, vin: vin, text: String(text.prefix(1600)), navigation: navigation)
        guard var encoded = try? JSONEncoder().encode(row) else { return }; encoded.append(10)
        let payload = encoded
        records.append(row); byteSizes.append(encoded.count); trimToBudget()
        let retained = records, destination = file
        writer.async {
            do {
                let data = payload
                if !FileManager.default.fileExists(atPath: destination.path) { try Data().write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
                let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size > 1048576 {
                    var checkpoint = Data()
                    for r in retained { checkpoint.append(try JSONEncoder().encode(r)); checkpoint.append(10) }
                    try checkpoint.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                } else {
                    let handle = try FileHandle(forWritingTo: destination); defer { try? handle.close() }
                    try handle.seekToEnd(); try handle.write(contentsOf: data)
                }
            } catch { /* A nonessential speech journal must not stop navigation or audio. */ }
        }
    }
    private func trimToBudget() {
        var bytes = byteSizes.reduce(0, +)
        while records.count > 2000 || bytes > 700000 {
            bytes -= byteSizes.removeFirst(); records.removeFirst()
        }
    }
    func waitForPendingWrites() { writer.sync {} } // Native durability tests only; never used in UI/audio paths.
    func rows(vin: String, from: Date, to: Date) -> [SpokenGuidance] { records.filter { $0.vin == vin && $0.at >= from && $0.at <= to } }
}
