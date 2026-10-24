import Foundation
#if canImport(UIKit)
import UIKit
import ImageIO
import CoreTransferable
import UniformTypeIdentifiers
#endif

enum AttachmentSafety {
    static let maximumPhotoBytes = 15_000_000
    static let maximumBackupBytes = 100_000_000
    static func base64Budget(bytes: Int) -> Int? {
        guard bytes > 0, bytes <= maximumPhotoBytes else { return nil }
        return (bytes + 2) / 3 * 4
    }
    static func dimensionsAllowed(width: Double, height: Double) -> Bool {
        width.isFinite && height.isFinite && width >= 1 && height >= 1 && width <= 100000 && height <= 100000 && width * height <= 100_000_000
    }
    static func writeBackup(state: Data, photos: [String: URL], destination: URL) throws {
        func invalid(_ message: String) -> NSError { NSError(domain: "BackupSafety", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        var budget = state.count + 1024
        for (name, url) in photos {
            let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard let encoded = base64Budget(bytes: bytes) else { throw invalid("사진 크기 오류") }
            budget += encoded + name.utf8.count * 6 + 16
            guard budget <= maximumBackupBytes else { throw invalid("백업이 100 MB를 초과함") }
        }
        // State is already serialized by the runtime; decoding a second full object would double peak memory.
        guard budget <= maximumBackupBytes, !state.isEmpty else { throw invalid("백업 원자료 형식·크기 오류") }
        let temporary = destination.appendingPathExtension("partial")
        guard !FileManager.default.fileExists(atPath: destination.path), !FileManager.default.fileExists(atPath: temporary.path) else { throw invalid("백업 파일 이름 충돌") }
        #if canImport(UIKit)
        let attributes: [FileAttributeKey: Any]? = [.protectionKey: FileProtectionType.complete]
        #else
        let attributes: [FileAttributeKey: Any]? = nil
        #endif
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: attributes) else { throw invalid("백업 파일 생성 실패") }
        let handle = try FileHandle(forWritingTo: temporary)
        var finished = false, written = 0
        defer { try? handle.close(); if !finished { try? FileManager.default.removeItem(at: temporary) } }
        func write(_ chunk: Data) throws {
            guard written + chunk.count <= maximumBackupBytes else { throw invalid("백업이 100 MB를 초과함") }
            try handle.write(contentsOf: chunk); written += chunk.count
        }
        try write(Data(#"{"kind":"YLCompanionBackup","schema":1,"state":"#.utf8))
        try write(state); try write(Data(#", "attachments":{"#.utf8))
        for (index, name) in photos.keys.sorted().enumerated() {
            let chunk: Data = try autoreleasepool {
                guard let url = photos[name] else { throw invalid("사진 경로 오류") }
                let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
                guard let data = try input.read(upToCount: maximumPhotoBytes + 1), base64Budget(bytes: data.count) != nil else { throw invalid("사진 크기 오류") }
                return try JSONSerialization.data(withJSONObject: [name: data.base64EncodedString()], options: [.withoutEscapingSlashes])
            }
            if index > 0 { try write(Data(",".utf8)) }
            try write(Data(chunk.dropFirst().dropLast()))
        }
        try write(Data("}}".utf8)); try handle.synchronize(); try handle.close()
        try FileManager.default.moveItem(at: temporary, to: destination); finished = true
    }
    #if canImport(UIKit)
    static func image(_ data: Data, maxPixel: Int = 2048) -> UIImage? {
        guard base64Budget(bytes: data.count) != nil,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              dimensionsAllowed(width: width.doubleValue, height: height.doubleValue) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(3072, max(256, maxPixel)), kCGImageSourceShouldCacheImmediately: true]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail)
    }
    static func jpeg(_ data: Data) -> Data? {
        autoreleasepool { image(data)?.jpegData(compressionQuality: 0.82) }
    }
    #endif
}

#if canImport(UIKit)
struct BoundedPhotoTransfer: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let input = try FileHandle(forReadingFrom: received.file)
            defer { try? input.close() }
            guard let data = try input.read(upToCount: AttachmentSafety.maximumPhotoBytes + 1),
                  AttachmentSafety.base64Budget(bytes: data.count) != nil else {
                throw NSError(domain: "PhotoSafety", code: 1, userInfo: [NSLocalizedDescriptionKey: "사진은 15 MB 이하로 선택 필요함"])
            }
            return BoundedPhotoTransfer(data: data)
        }
    }
}
#endif
