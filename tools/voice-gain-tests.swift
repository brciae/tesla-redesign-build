import Foundation

func require(_ condition: Bool, _ message: String) { precondition(condition, message) }
func wav(_ values: [Int16]) -> Data {
    var d = Data("RIFF".utf8)
    func put<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; withUnsafeBytes(of: &v) { d.append(contentsOf: $0) } }
    put(UInt32(36 + values.count * 2)); d.append(Data("WAVEfmt ".utf8))
    put(UInt32(16)); put(UInt16(1)); put(UInt16(1)); put(UInt32(24000)); put(UInt32(48000)); put(UInt16(2)); put(UInt16(16))
    d.append(Data("data".utf8)); put(UInt32(values.count * 2)); values.forEach { put($0) }
    return d
}
@main struct VoiceGainTests {
static func main() throws {
let original = wav([0, 1000, -1000, 20000, -20000, 32767, -32768])
require(try VoiceGainPolicy.amplifiedWAV(original, gain: 1) == original, "100% must preserve cache bytes")
require(try VoiceGainPolicy.amplifiedWAV(original, gain: 0.5) == original, "<=100% uses player attenuation")
let doubled = try VoiceGainPolicy.amplifiedWAV(original, gain: 2)
let expected = wav([0, 2000, -2000, 32767, -32768, 32767, -32768])
require(doubled == expected, "200% must double quiet samples and clamp loud peaks without wrap")
require(original == wav([0,1000,-1000,20000,-20000,32767,-32768]), "Original cache modified")
require(VoiceGainPolicy.gain(.nan) == 1 && VoiceGainPolicy.gain(9) == 2 && VoiceGainPolicy.gain(-1) == 0, "Gain bounds")
for invalid in [Data(), Data(original.prefix(20)), Data(original.dropLast())] {
    do { _ = try VoiceGainPolicy.amplifiedWAV(invalid, gain: 2); fatalError("Malformed WAV accepted") } catch {}
}
// A non-audio RIFF chunk must survive and be skipped, including its odd-byte padding.
var odd = original; odd.insert(contentsOf: [74,85,78,75,1,0,0,0,42,0], at: 12)
var length = UInt32(odd.count - 8).littleEndian
withUnsafeBytes(of: &length) { odd.replaceSubrange(4..<8, with: $0) }
let oddResult = try VoiceGainPolicy.amplifiedWAV(odd, gain: 2)
require(oddResult[12..<22] == odd[12..<22] && oddResult.suffix(14) == expected.suffix(14), "Odd metadata chunk corrupted")
print("PASS: 200% signal gain, 100% identity, saturation, malformed WAV, cache preservation and RIFF metadata")
func sampleWAV(format: UInt16, bits: UInt16, payload: [UInt8]) -> Data {
    var d = wav([])
    func put<T: FixedWidthInteger>(_ value: T, at offset: Int) {
        var v = value.littleEndian; withUnsafeBytes(of: &v) { d.replaceSubrange(offset..<offset + $0.count, with: $0) }
    }
    put(format, at: 20); put(bits / 8, at: 32); put(bits, at: 34)
    put(UInt32(24000 * Int(bits / 8)), at: 28); put(UInt32(payload.count), at: 40)
    d.append(contentsOf: payload); put(UInt32(d.count - 8), at: 4)
    return d
}
let pcm24 = sampleWAV(format: 1, bits: 24, payload: [0xE8,3,0, 0x18,0xFC,0xFF])
require(try VoiceGainPolicy.amplifiedWAV(pcm24, gain: 2).suffix(6) == Data([0xD0,7,0, 0x30,0xF8,0xFF]), "24-bit signed gain")
let pcm32 = sampleWAV(format: 1, bits: 32, payload: [0xE8,3,0,0, 0x18,0xFC,0xFF,0xFF])
require(try VoiceGainPolicy.amplifiedWAV(pcm32, gain: 2).suffix(8) == Data([0xD0,7,0,0, 0x30,0xF8,0xFF,0xFF]), "32-bit signed gain")
let pcm8 = sampleWAV(format: 1, bits: 8, payload: [128,138,118,255])
require(try VoiceGainPolicy.amplifiedWAV(pcm8, gain: 2).suffix(4) == Data([128,148,108,255]), "8-bit centered gain")
for bits: UInt16 in [32,64] {
    var payload = Data()
    for value: Double in [0.25,-0.25,0.75,Double.nan] {
        if bits == 32 { var raw = Float(value).bitPattern.littleEndian; withUnsafeBytes(of: &raw) { payload.append(contentsOf: $0) } }
        else { var raw = value.bitPattern.littleEndian; withUnsafeBytes(of: &raw) { payload.append(contentsOf: $0) } }
    }
    let result = try VoiceGainPolicy.amplifiedWAV(sampleWAV(format: 3, bits: bits, payload: [UInt8](payload)), gain: 2)
    let values: [Double] = stride(from: 44, to: result.count, by: Int(bits / 8)).map { at in
        result.withUnsafeBytes { buffer in bits == 32 ? Double(Float(bitPattern: UInt32(littleEndian: buffer.loadUnaligned(fromByteOffset: at, as: UInt32.self)))) : Double(bitPattern: UInt64(littleEndian: buffer.loadUnaligned(fromByteOffset: at, as: UInt64.self))) }
    }
    require(values == [0.5,-0.5,1,0], "Float WAV gain and nonfinite sanitization")
}
print("PASS: PCM8/16/24/32 and floating32/64, including unaligned RIFF payloads")

}
}
