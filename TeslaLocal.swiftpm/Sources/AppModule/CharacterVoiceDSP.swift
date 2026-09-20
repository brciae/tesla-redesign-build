import Foundation

/// v35 character shaping. A plain pitch shifter moves the vocal-tract resonances (formants) together
/// with the pitch, which is why "raise the pitch" alone sounds like helium rather than like a Japanese
/// anime voice. Anime delivery is instead a *short vocal tract* (formants stretched upward) with a
/// moderate F0 and a lot of breath, so this stage warps only the spectral envelope and adds aspiration,
/// leaving F0 to the pitch unit in VoiceEffects.
///
/// Per frame: FFT → log magnitude → envelope (moving average wider than the highest F0) → frequency-warp
/// the envelope → apply the difference as a gain → inverse FFT → overlap-add.
enum CharacterVoiceDSP {
    static let frame = 1024
    static let hop = 256
    /// Envelope smoothing window in bins. At 44.1 kHz one bin is ~43 Hz, so 17 bins ~ 730 Hz:
    /// wider than the highest F0 we produce, which keeps harmonics out of the envelope.
    static let smoothing = 17

    /// How much of `formant` applies at each frequency. Anime timbre needs the 1.5–3 kHz region lifted
    /// while F1 (~500–700 Hz) stays close to where it was; lifting everything equally just widens the
    /// vowels ("aah"). Values are interpolated between these anchors.
    private static let shapeHz: [Float] = [0, 350, 900, 1600, 3000, 6000, 9000]
    private static let shapeWeight: [Float] = [0, 0.06, 0.45, 1.0, 0.96, 0.45, 0.15]

    /// - formant: vocal-tract stretch for the 1.5–3 kHz region (1 = untouched, 1.4 = very young).
    /// - breath: aspiration noise level.
    /// - breathWarmth: 0 keeps breath in the 2.5–9 kHz band, 1 extends it down to ~1.1 kHz (a thicker,
    ///   closer sound rather than a hiss) — this is what makes a sultry delivery read as sultry.
    /// - life: pitch-contour expansion. A TTS contour is flat, which is most of the "machine" impression;
    ///   deviations from the running mean F0 are multiplied, so the intonation the engine did produce
    ///   becomes noticeably more animated.
    /// - vibrato: depth in cents of a slow 4.6 Hz modulation plus a little random drift, so held vowels
    ///   are never perfectly steady (perfectly steady pitch is the other half of the machine impression).
    /// - thickness: detuned chorus copies — the "thick / lush" quality.
    /// - warmth: gentle saturation that adds low-order harmonics.
    static func apply(_ samples: [Float], sampleRate: Int, formant: Float, breath: Float,
                      breathWarmth: Float = 0, life: Float = 0, vibrato: Float = 0,
                      thickness: Float = 0, warmth: Float = 0) -> [Float] {
        let warp = min(1.4, max(1.0, formant))
        let air = min(0.4, max(0, breath))
        let airWarmth = min(1, max(0, breathWarmth))
        let contour = min(1, max(0, life))
        let wobble = min(60, max(0, vibrato))
        let thick = min(0.5, max(0, thickness))
        let drive = min(0.6, max(0, warmth))
        let active = warp > 1.001 || air > 0.001 || contour > 0.001 || wobble > 0.5 || thick > 0.005 || drive > 0.005
        guard samples.count > frame, active else { return samples }
        var shaped = samples
        if contour > 0.001 || wobble > 0.5 {
            shaped = animatePitch(shaped, sampleRate: sampleRate, life: contour, vibrato: wobble)
        }
        if warp > 1.001 { shaped = warpEnvelope(shaped, sampleRate: sampleRate, formant: warp) }
        if thick > 0.005 { shaped = thicken(shaped, sampleRate: sampleRate, amount: thick) }
        if drive > 0.005 { shaped = saturate(shaped, amount: drive) }
        if air > 0.001 { shaped = addBreath(shaped, sampleRate: sampleRate, amount: air, warmth: airWarmth) }
        return shaped
    }

    // MARK: - pitch contour animation

    /// Reads the signal through a fractionally interpolated delay whose length changes sample by sample.
    /// A read speed of r gives an instantaneous pitch ratio r, so a per-sample cents curve becomes a
    /// pitch bend. The curve is zero-mean by construction (deviation from the running mean F0) and the
    /// delay is pulled gently back to the middle of the buffer, so nothing drifts or runs out of room.
    private static func animatePitch(_ samples: [Float], sampleRate: Int, life: Float, vibrato: Float) -> [Float] {
        let sr = Float(sampleRate)
        let cents = contourCents(samples, sampleRate: sampleRate, life: life)
        let centre = Float(sampleRate) * 0.06                     // 60 ms of headroom either way
        var delay = centre
        var out = [Float](repeating: 0, count: samples.count)
        let vibratoRate: Float = 4.6
        var drift: Float = 0
        var seed: UInt64 = 0xD1B54A32D192ED03
        // The delay step is taken as the *linear* form of the pitch ratio, −ln2/1200 × cents, which is
        // exactly antisymmetric: a +100 cent excursion moves the delay as far as a −100 cent one moves it
        // back. The exact 1 − 2^(c/1200) is not, and with it the delay walked into its floor, after which
        // only the downward half of each bend survived and the voice drifted flat — the v37 renders came
        // out 340–590 cents low. The cents curve is zero-mean by construction, so this integrates to zero.
        let centsToStep: Float = -0.000577623                     // −ln(2)/1200
        for i in samples.indices {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let noise = Self.signedNoise(seed)
            drift += 0.0008 * (noise - drift)                     // slow random wander, not hiss
            let lfo = sin(2 * Float.pi * vibratoRate * Float(i) / sr)
            var target = cents[i] + vibrato * (0.8 * lfo + 4 * drift)
            // Ease off as the delay nears either end, so the bend is never clipped on one side only.
            let room = (delay - 2) / max(1, centre * 1.9 - 2)      // 0 at the floor, 1 at the ceiling
            if target > 0 { target *= min(1, max(0, room * 4)) }
            if target < 0 { target *= min(1, max(0, (1 - room) * 4)) }
            let step = centsToStep * min(300, max(-300, target))
            delay += step - 0.00004 * (delay - centre)            // ~0.6 s pull, only to mop up residue
            delay = min(centre * 1.9, max(2, delay))
            let read = Float(i) - delay
            if read <= 0 { out[i] = samples[i]; continue }
            let i0 = Int(read), frac = read - Float(Int(read))
            let a = samples[min(samples.count - 1, i0)]
            let b = samples[min(samples.count - 1, i0 + 1)]
            out[i] = a + (b - a) * frac
        }
        return out
    }

    /// Per-sample cents offset that exaggerates the engine's own intonation.
    private static func contourCents(_ samples: [Float], sampleRate: Int, life: Float) -> [Float] {
        let step = max(1, sampleRate / 100)                       // 10 ms analysis hop
        let window = max(step * 4, sampleRate / 25)               // 40 ms window
        let minLag = sampleRate / 420, maxLag = sampleRate / 70   // 70–420 Hz
        var frames: [Float] = []                                  // log2 F0, 0 where unvoiced
        var index = 0
        while index + window <= samples.count {
            var energy: Float = 0
            for k in index..<(index + window) { energy += samples[k] * samples[k] }
            let rms = sqrt(energy / Float(window))
            var value: Float = 0
            if rms > 0.01 {
                var best = 0, bestScore: Float = 0
                var zero: Float = 0
                for k in index..<(index + window) { zero += samples[k] * samples[k] }
                var lag = minLag
                while lag <= maxLag {
                    var sum: Float = 0
                    var k = index
                    while k + lag < index + window { sum += samples[k] * samples[k + lag]; k += 1 }
                    if sum > bestScore { bestScore = sum; best = lag }
                    lag += 1
                }
                if best > 0, bestScore > 0.3 * zero { value = log2(Float(sampleRate) / Float(best)) }
            }
            frames.append(value)
            index += step
        }
        guard !frames.isEmpty else { return [Float](repeating: 0, count: samples.count) }
        // Two references, not one. A spoken sentence drifts downward from start to end (declination);
        // exaggerating THAT just makes the voice trail off into a mumble, which is what v37 did (the tail
        // of each line fell from 258 Hz to 188 Hz). So the slow component — anything slower than about a
        // second — is treated as the baseline, and only the faster accent movement on top of it is scaled.
        func movingMean(_ values: [Float], span: Int, voicedOnly: Bool = true) -> [Float] {
            var out = [Float](repeating: 0, count: values.count)
            for i in values.indices {
                var sum: Float = 0, count = 0
                for k in max(0, i - span)...min(values.count - 1, i + span) where !voicedOnly || values[k] > 0 {
                    sum += values[k]; count += 1
                }
                out[i] = count > 0 ? sum / Float(count) : 0
            }
            return out
        }
        let slow = movingMean(frames, span: 100)          // ~2 s window: the declination baseline
        var perFrame = [Float](repeating: 0, count: frames.count)
        for i in frames.indices where frames[i] > 0 && slow[i] > 0 {
            perFrame[i] = (frames[i] - slow[i]) * 1200
        }
        for i in perFrame.indices { perFrame[i] *= life }
        // Final guard: remove anything that survives longer than about half a second. Without it the
        // truncated averaging window at the end of a line leaves a sustained downward bend, and the tail
        // of every sentence sinks (measured: a 237 Hz ending fell to 172 Hz).
        let sustained = movingMean(perFrame, span: 25, voicedOnly: false)
        for i in perFrame.indices { perFrame[i] = min(220, max(-220, perFrame[i] - sustained[i])) }
        // Smooth across frames so the bend glides instead of stepping, then expand to per-sample.
        var smooth = perFrame
        for _ in 0..<3 {
            var next = smooth
            for i in 1..<(smooth.count - 1) { next[i] = (smooth[i - 1] + 2 * smooth[i] + smooth[i + 1]) / 4 }
            smooth = next
        }
        var out = [Float](repeating: 0, count: samples.count)
        for i in samples.indices {
            let position = Float(i) / Float(step)
            let i0 = min(smooth.count - 1, Int(position))
            let i1 = min(smooth.count - 1, i0 + 1)
            let frac = position - Float(Int(position))
            out[i] = smooth[i0] + (smooth[i1] - smooth[i0]) * frac
        }
        return out
    }

    // MARK: - thickness and warmth

    /// Two slowly detuned copies (classic chorus). Gives the voice body without turning it into an echo.
    private static func thicken(_ samples: [Float], sampleRate: Int, amount: Float) -> [Float] {
        let sr = Float(sampleRate)
        var out = samples
        let voices: [(base: Float, depth: Float, rate: Float, gain: Float)] = [
            (0.018, 0.0028, 0.61, 0.85), (0.027, 0.0034, 0.43, 0.7)
        ]
        for voice in voices {
            for i in samples.indices {
                let delay = (voice.base + voice.depth * sin(2 * Float.pi * voice.rate * Float(i) / sr)) * sr
                let read = Float(i) - delay
                if read <= 1 { continue }
                let i0 = Int(read), frac = read - Float(Int(read))
                let a = samples[min(samples.count - 1, i0)]
                let b = samples[min(samples.count - 1, i0 + 1)]
                out[i] += amount * voice.gain * (a + (b - a) * frac)
            }
        }
        var peak: Float = 0
        for v in out { peak = max(peak, abs(v)) }
        if peak > 0.98 { let g = 0.98 / peak; for i in out.indices { out[i] *= g } }
        return out
    }

    /// Soft saturation: adds low-order harmonics so the tone is not spectrally sterile.
    private static func saturate(_ samples: [Float], amount: Float) -> [Float] {
        let drive = 1 + 6 * amount
        let norm = tanh(drive)
        return samples.map { value in
            let wet = tanh(drive * value) / norm
            let mixed = value * (1 - amount) + wet * amount
            return mixed.isFinite ? mixed : value
        }
    }

    /// Zero-mean white noise in −1...1. The earlier version shifted the top bit away and produced only
    /// positive values, which put a DC offset under the breath and walked the vibrato delay into its
    /// floor — after which only the downward half of the modulation survived and sentences sank at the end.
    private static func signedNoise(_ seed: UInt64) -> Float {
        Float(Int32(bitPattern: UInt32(truncatingIfNeeded: seed >> 32))) / Float(Int32.max)
    }

    // MARK: - envelope warp

    private static func warpEnvelope(_ samples: [Float], sampleRate: Int, formant: Float) -> [Float] {
        let n = frame, bins = n / 2 + 1
        let window = (0..<n).map { 0.5 - 0.5 * cos(2 * Float.pi * Float($0) / Float(n)) }
        let fft = FFT(size: n)

        // Source bin for every output bin: warping the envelope up by s(f) means reading it from f / s(f).
        var source = [Float](repeating: 0, count: bins)
        for k in 0..<bins {
            let hz = Float(k) * Float(sampleRate) / Float(n)
            let scale = 1 + (formant - 1) * weight(hz)
            source[k] = min(Float(bins - 1), max(0, Float(k) / scale))
        }

        var out = [Float](repeating: 0, count: samples.count + n)
        var norm = [Float](repeating: 0, count: samples.count + n)
        var real = [Float](repeating: 0, count: n)
        var imag = [Float](repeating: 0, count: n)
        var logMag = [Float](repeating: 0, count: bins)
        var envelope = [Float](repeating: 0, count: bins)

        var start = 0
        while start + n <= samples.count {
            for i in 0..<n { real[i] = samples[start + i] * window[i]; imag[i] = 0 }
            fft.forward(&real, &imag)
            for k in 0..<bins {
                let m = sqrt(real[k] * real[k] + imag[k] * imag[k])
                logMag[k] = log(m + 1e-9)
            }
            movingAverage(logMag, into: &envelope, width: smoothing)
            for k in 0..<bins {
                let x = source[k]
                let i0 = Int(x), i1 = min(bins - 1, i0 + 1)
                let f = x - Float(i0)
                let warped = envelope[i0] * (1 - f) + envelope[i1] * f
                let gain = min(4, max(0.25, exp(warped - envelope[k])))
                real[k] *= gain; imag[k] *= gain
                if k > 0 && k < bins - 1 {                      // keep the spectrum conjugate-symmetric
                    real[n - k] *= gain; imag[n - k] *= gain
                }
            }
            fft.inverse(&real, &imag)
            for i in 0..<n {
                out[start + i] += real[i] * window[i]
                norm[start + i] += window[i] * window[i]
            }
            start += hop
        }
        var result = [Float](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            let w = norm[i]
            result[i] = w > 1e-5 ? out[i] / w : samples[i]
            if !result[i].isFinite { result[i] = samples[i] }
        }
        return result
    }

    private static func weight(_ hz: Float) -> Float {
        if hz <= shapeHz[0] { return shapeWeight[0] }
        for i in 1..<shapeHz.count where hz <= shapeHz[i] {
            let span = shapeHz[i] - shapeHz[i - 1]
            let t = span > 0 ? (hz - shapeHz[i - 1]) / span : 0
            return shapeWeight[i - 1] + (shapeWeight[i] - shapeWeight[i - 1]) * t
        }
        return 0
    }

    /// Box filter with mirrored edges, so the envelope does not sag at DC or Nyquist.
    private static func movingAverage(_ input: [Float], into output: inout [Float], width: Int) {
        let count = input.count, half = width / 2
        for k in 0..<count {
            var sum: Float = 0
            for d in -half...half {
                var i = k + d
                if i < 0 { i = -i }
                if i >= count { i = 2 * (count - 1) - i }
                sum += input[max(0, min(count - 1, i))]
            }
            output[k] = sum / Float(width)
        }
    }

    // MARK: - breath

    /// Aspiration noise follows the signal's own amplitude envelope, so it breathes with the voice
    /// instead of hissing under the silences. Band-limited to 2.5–9 kHz where breath actually sits.
    private static func addBreath(_ samples: [Float], sampleRate: Int, amount: Float, warmth: Float) -> [Float] {
        var noise = [Float](repeating: 0, count: samples.count)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for i in samples.indices {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            noise[i] = Self.signedNoise(seed)
        }
        // Warmth pulls the breath band down: airy hiss at 0, a close breathy body at 1.
        bandpass(&noise, sampleRate: sampleRate, low: 2500 - 1400 * warmth, high: 9000 - 1500 * warmth)
        // Amplitude envelope: rectify, then a one-pole smoother at ~30 Hz.
        let alpha = min(0.9, Float(30) / Float(sampleRate) * 6.283)
        var env: Float = 0
        var peak: Float = 0
        var result = samples
        for i in samples.indices {
            env += alpha * (abs(samples[i]) - env)
            // 0.65 keeps `amount` on the same scale the presets were tuned on (0.1 audible, 0.26 very breathy).
            result[i] = samples[i] + amount * noise[i] * env * 0.65
            peak = max(peak, abs(result[i]))
        }
        if peak > 0.98 { let g = 0.98 / peak; for i in result.indices { result[i] *= g } }
        return result.map { $0.isFinite ? $0 : 0 }
    }

    /// Two cascaded one-pole sections: high-pass then low-pass. Enough shaping for noise.
    private static func bandpass(_ x: inout [Float], sampleRate: Int, low: Float, high: Float) {
        let sr = Float(sampleRate)
        let a = exp(-2 * Float.pi * low / sr)
        var prevIn: Float = 0, prevOut: Float = 0
        for i in x.indices {                               // high-pass
            let out = a * (prevOut + x[i] - prevIn)
            prevIn = x[i]; prevOut = out; x[i] = out
        }
        let b = exp(-2 * Float.pi * high / sr)
        var last: Float = 0
        for i in x.indices {                               // low-pass
            last = (1 - b) * x[i] + b * last
            x[i] = last
        }
        var scale: Float = 0
        for v in x { scale = max(scale, abs(v)) }
        if scale > 1e-6 { for i in x.indices { x[i] /= scale } }
    }
}

/// Small radix-2 FFT. Deliberately dependency-free: the offline path runs once per sentence, and a
/// hand-rolled transform avoids the packed-format pitfalls of the vDSP real-FFT API.
struct FFT {
    let size: Int
    private let levels: Int
    private let cosTable: [Float]
    private let sinTable: [Float]

    init(size: Int) {
        self.size = size
        self.levels = Int(log2(Double(size)).rounded())
        var c = [Float](repeating: 0, count: size / 2)
        var s = [Float](repeating: 0, count: size / 2)
        for i in 0..<size / 2 {
            let angle = 2 * Double.pi * Double(i) / Double(size)
            c[i] = Float(cos(angle)); s[i] = Float(sin(angle))
        }
        cosTable = c; sinTable = s
    }

    func forward(_ real: inout [Float], _ imag: inout [Float]) { transform(&real, &imag, inverse: false) }

    func inverse(_ real: inout [Float], _ imag: inout [Float]) {
        transform(&imag, &real, inverse: true)             // swapping the arrays performs the inverse
        let scale = Float(1) / Float(size)
        for i in 0..<size { real[i] *= scale; imag[i] *= scale }
    }

    private func transform(_ real: inout [Float], _ imag: inout [Float], inverse: Bool) {
        // Bit-reversal permutation.
        var j = 0
        for i in 1..<size {
            var bit = size >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j |= bit
            if i < j { real.swapAt(i, j); imag.swapAt(i, j) }
        }
        var span = 2
        while span <= size {
            let step = size / span
            var start = 0
            while start < size {
                var k = 0
                for i in start..<(start + span / 2) {
                    let partner = i + span / 2
                    let c = cosTable[k], s = -sinTable[k]
                    let tr = real[partner] * c - imag[partner] * s
                    let ti = real[partner] * s + imag[partner] * c
                    real[partner] = real[i] - tr; imag[partner] = imag[i] - ti
                    real[i] += tr; imag[i] += ti
                    k += step
                }
                start += span
            }
            span <<= 1
        }
        _ = inverse
        _ = levels
    }
}
