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

}
}
