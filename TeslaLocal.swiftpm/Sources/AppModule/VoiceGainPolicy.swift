import Foundation

/// Playback-only gain. Cached Typecast audio remains unchanged; player volume stays <= 1.
enum VoiceGainPolicy {
    static func gain(_ value: Double) -> Double { value.isFinite ? min(2, max(0, value)) : 1 }
    static func paddedTail(_ source: Data, seconds: Double = 0.6) -> Data {
        guard source.count >= 12, source.count <= 32_000_000, seconds.isFinite, seconds > 0, seconds <= 1 else { return source }
        let bytes = [UInt8](source)
        func word(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        func size(_ o: Int) -> Int { word(o) | word(o + 2) << 16 }
        guard String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF", String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE", size(4) == bytes.count - 8 else { return source }
        var offset = 12, byteRate = 0, alignment = 0, bits = 0, format = 0
        while offset + 8 <= bytes.count {
            let count = size(offset + 4), start = offset + 8
            guard count <= bytes.count - start else { return source }
            let id = String(bytes: bytes[offset..<offset + 4], encoding: .ascii)
            if id == "fmt " {
                guard count >= 16 else { return source }
                format = word(start); let channels = word(start + 2), sampleRate = size(start + 4)
                byteRate = size(start + 8); alignment = word(start + 12); bits = word(start + 14)
                if format == 0xFFFE { guard count >= 40 else { return source }; format = word(start + 24) }
                guard (1...8).contains(channels), (8000...192000).contains(sampleRate), [8,16,24,32,64].contains(bits),
                      alignment == channels * (bits / 8), byteRate == sampleRate * alignment else { return source }
            } else if id == "data" {
                guard (format == 1 && [8,16,24,32].contains(bits)) || (format == 3 && [32,64].contains(bits)) else { return source }
                guard byteRate > 0, alignment > 0, count % alignment == 0, start + count == bytes.count else { return source }
                let requested = Double(byteRate) * seconds
                guard requested <= 1_048_576 else { return source }
                let extra = Int(requested) / alignment * alignment
                guard extra > 0, bytes.count + extra - 8 <= Int(UInt32.max), count + extra <= Int(UInt32.max) else { return source }
                var result = Data(bytes)
                result.append(Data(repeating: format == 1 && bits == 8 ? 128 : 0, count: extra))
                func put(_ value: Int, _ at: Int) {
                    var value = UInt32(value).littleEndian
                    withUnsafeBytes(of: &value) { result.replaceSubrange(at..<at + 4, with: $0) }
                }
                put(count + extra, offset + 4); put(result.count - 8, 4)
                return result
            }
            offset = start + count + (count & 1)
        }
        return source
    }
    static func amplifiedWAV(_ source: Data, gain requested: Double) throws -> Data {
        let boost = gain(requested)
        guard boost > 1 else { return source }
        func invalid() -> NSError { NSError(domain: "VoiceGain", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "음성 오디오 형식을 확인할 수 없어 증폭하지 못했습니다."]) }
        guard source.count <= 32_000_000 else { throw invalid() }
        let bytes = [UInt8](source)
        func word(_ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }
        func size(_ offset: Int) -> Int { word(offset) | word(offset + 2) << 16 }
        guard bytes.count >= 12, String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE" else { throw invalid() }
        var offset = 12, format = 0, bits = 0, alignment = 0
        var ranges: [Range<Int>] = []
        while offset + 8 <= bytes.count {
            let count = size(offset + 4), start = offset + 8
            guard count >= 0, count <= bytes.count - start else { throw invalid() }
            let id = String(bytes: bytes[offset..<offset + 4], encoding: .ascii)
            if id == "fmt " {
                guard count >= 16 else { throw invalid() }
                format = word(start); alignment = word(start + 12); bits = word(start + 14)
                if format == 0xFFFE {
                    guard count >= 40, word(start + 16) >= 22 else { throw invalid() }
                    format = word(start + 24)
                }
            } else if id == "data" { ranges.append(start..<start + count) }
            offset = start + count + (count & 1)
        }
        let sampleBytes = bits / 8
        guard (format == 1 && [8,16,24,32].contains(bits)) || (format == 3 && [32,64].contains(bits)),
              alignment > 0, sampleBytes > 0, alignment % sampleBytes == 0, !ranges.isEmpty,
              ranges.allSatisfy({ $0.count % alignment == 0 }) else { throw invalid() }
        var result = source
        result.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            for range in ranges {
                for position in stride(from: range.lowerBound, to: range.upperBound, by: sampleBytes) {
                    if format == 3 {
                        if bits == 32 {
                            let raw = buffer.loadUnaligned(fromByteOffset: position, as: UInt32.self)
                            let value = Double(Float(bitPattern: UInt32(littleEndian: raw)))
                            let output = Float(value.isFinite ? min(1, max(-1, value * boost)) : 0)
                            for index in 0..<4 { buffer[position + index] = UInt8(truncatingIfNeeded: output.bitPattern >> (index * 8)) }
                        } else {
                            let raw = buffer.loadUnaligned(fromByteOffset: position, as: UInt64.self)
                            let value = Double(bitPattern: UInt64(littleEndian: raw))
                            let output = value.isFinite ? min(1, max(-1, value * boost)) : 0
                            for index in 0..<8 { buffer[position + index] = UInt8(truncatingIfNeeded: output.bitPattern >> (index * 8)) }
                        }
                    } else if bits == 8 {
                        let output = min(127, max(-128, Int((Double(Int(buffer[position]) - 128) * boost).rounded())))
                        buffer[position] = UInt8(output + 128)
                    } else {
                        var value: Int64 = 0
                        for index in 0..<sampleBytes { value |= Int64(buffer[position + index]) << (index * 8) }
                        let sign: Int64 = 1 << (bits - 1)
                        if value & sign != 0 { value -= 1 << bits }
                        let output = Int64(min(Double(sign - 1), max(-Double(sign), (Double(value) * boost).rounded())))
                        for index in 0..<sampleBytes { buffer[position + index] = UInt8(truncatingIfNeeded: output >> (index * 8)) }
                    }
                }
            }
        }
        return result
    }
}
