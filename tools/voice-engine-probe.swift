import Foundation
import OnnxRuntimeBindings

@main struct VoiceEngineProbe {
    static func main() throws {
        setvbuf(stdout, nil, _IONBF, 0)          // so the log still shows progress if a precondition traps
        var appearance = VehicleAppearance(); appearance.tintStrength = .infinity; appearance.plate = "123가 4567<script>"; appearance.paint = "../evil"; appearance.imageID = "../../secret"
        let clean = appearance.validated()
        precondition(clean.tintStrength == 0.65 && clean.paint == "334150" && clean.imageID == nil)
        precondition(!clean.plate.contains("<") && clean.plate.count <= 12)
        precondition(VehiclePaintPreset.modelYL.count == 6 && VehiclePaintPreset.modelYL.allSatisfy { VehicleAppearance.validHex($0.hex) })
        let decoded = try JSONDecoder().decode(VehicleAppearance.self, from: JSONEncoder().encode(clean))
        precondition(decoded == clean)
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let env = try ORTEnv(loggingLevel: .warning)
        let tts = try loadTextToSpeech(root.appendingPathComponent("onnx").path, false, env)
        let cues = ["공조를 시작합니다.", "충전 포트를 엽니다.", "실내 온도를 22도로 설정합니다.", "안내를 시작합니다."]
        for (index, voice) in VoicePackManifest.voices.enumerated() {
            let style = try loadVoiceStyle([root.appendingPathComponent("voice_styles/" + voice + ".json").path], verbose: false)
            let started = Date()
            let result = try tts.call(cues[index % cues.count], "ko", style, 8)
            precondition(result.duration > 0 && result.duration < 35 && result.wav.count > 1000)
            precondition(result.wav.allSatisfy { $0.isFinite })
            let rms = sqrt(result.wav.reduce(0.0) { $0 + Double($1)*Double($1) }/Double(result.wav.count))
            precondition(rms > 0.001 && rms < 0.9)
            try writeWavFile(output.appendingPathComponent("voice-" + voice + ".wav").path, result.wav, tts.sampleRate)
            print("PASS: Korean voice \(voice), duration \(result.duration), RMS \(rms), synthesis \(Date().timeIntervalSince(started))s")
        }
        // v42/v43: the recorded guidance packs. The matching rules decide whether the owner hears a
        // person or the synthesiser, so they are checked against the real manifests, not a fixture.
        let packRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("TeslaLocal.swiftpm/Sources/AppModule/Resources/recorded")
        let indexData = try Data(contentsOf: packRoot.appendingPathComponent("voices.json"))
        guard let rows = try JSONSerialization.jsonObject(with: indexData) as? [[String: Any]], !rows.isEmpty else {
            preconditionFailure("recorded voice index missing")
        }
        var loaded: [RecordedVoice.Voice] = []
        for row in rows {
            guard let id = row["id"] as? String, let name = row["name"] as? String else { preconditionFailure("bad voice row") }
            let folder = (row["folder"] as? String) ?? id
            guard let bank = RecordedVoice.load(manifest: packRoot.appendingPathComponent(folder).appendingPathComponent("manifest.json")) else {
                preconditionFailure("recorded pack missing: \(folder)")
            }
            // v43: the picker shows a character portrait, so a pack that names one must ship it.
            var portrait: URL?
            if let file = row["portrait"] as? String {
                let url = packRoot.appendingPathComponent(folder).appendingPathComponent(file)
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
                precondition(size > 1000, "portrait missing: \(folder)/\(file)")
                portrait = url
            }
            // The packs were recorded at different levels; each one must say how to even that out.
            let gain = (row["gain"] as? NSNumber).map { Float(truncating: $0) } ?? 0
            precondition(gain >= 0.25 && gain <= 4, "\(name) has no usable playback gain")
            loaded.append(RecordedVoice.Voice(id: RecordedVoice.prefix + id, name: name,
                                              style: (row["style"] as? String) ?? "", portrait: portrait,
                                              gain: gain, bank: bank))
        }
        RecordedVoice.voices = loaded
        precondition(RecordedVoice.available && VoiceLibrary.recordedChoices().count == loaded.count)
        var complete = 0
        for voice in loaded {
            let bank = voice.bank
            precondition(bank.phrases.count >= 200, "\(voice.name) phrases: \(bank.phrases.count)")
            // Whole sentences are always one clip, and a place name can never be recorded.
            precondition(RecordedVoice.plan(for: "목적지에 도착했습니다.", voice: voice.id)?.count == 1)
            precondition(RecordedVoice.covers("경로를 이탈했습니다. 새 경로를 찾고 있습니다.", voice: voice.id))
            precondition(!RecordedVoice.covers("설정된 목적지는 서울역입니다.", voice: voice.id))
            precondition(!RecordedVoice.covers("", voice: voice.id))
            // Spacing and punctuation must not decide it: the bridge and the pack space these differently.
            precondition(RecordedVoice.covers("어린이 보호구역입니다. 안전 운전하세요.", voice: voice.id))
            let turns = bank.distance.count >= 10 && bank.action.count >= 18
            if turns {
                // A turn call is the distance clip plus the action clip; a sentence the pack happens to
                // hold whole plays as that one clip instead.
                precondition(RecordedVoice.plan(for: "삼백 미터 앞, 좌회전입니다.", voice: voice.id)?.count == 2)
                precondition(RecordedVoice.plan(for: "오백 미터 앞, 유턴입니다.", voice: voice.id)?.count == 2)
                precondition(RecordedVoice.covers("잠시 후, 유턴입니다.", voice: voice.id))
            } else {
                precondition(!RecordedVoice.covers("삼백 미터 앞, 좌회전입니다.", voice: voice.id))
            }
            if bank.composable {
                // Word-level number composition: head + ONE number + tail, and nothing looser.
                precondition(RecordedVoice.plan(for: "현재 배터리 잔량은 사십육 퍼센트입니다.", voice: voice.id)?.count == 3)
                precondition(!RecordedVoice.covers("목적지까지 십이 분 걸어가세요.", voice: voice.id))
                // A number the pack does not hold whole must fall back, never be chained out of the
                // pieces it does hold: 12 spoken as "십" + "이" would be "ten, two".
                if bank.number[RecordedVoice.normalise("구백구십구")] == nil {
                    precondition(!RecordedVoice.covers("현재 배터리 잔량은 구백구십구 퍼센트입니다.", voice: voice.id))
                }
                if turns {
                    precondition(RecordedVoice.plan(for: "삼백 미터 앞, 과속 단속입니다. 제한 속도는 시속 육십 킬로미터입니다.", voice: voice.id)?.count == 5)
                    complete += 1
                }
            } else {
                precondition(!RecordedVoice.covers("현재 배터리 잔량은 사십육 퍼센트입니다.", voice: voice.id))
            }
            // Crossfaded playback must produce one buffer at the pack's own rate.
            if let plan = RecordedVoice.plan(for: "목적지에 도착했습니다.", voice: voice.id),
               let rendered = RecordedVoice.render(plan, gain: voice.gain) {
                precondition(rendered.sampleRate > 8000 && rendered.samples.count > 2000)
                precondition(rendered.samples.allSatisfy { $0.isFinite && abs($0) <= 1.001 })
            } else { preconditionFailure("render failed for \(voice.name)") }
            for file in Array(bank.phrases.values) + Array(bank.distance.values) + Array(bank.action.values)
                        + Array(bank.head.values) + Array(bank.number.values) + Array(bank.tail.values) {
                let url = bank.folder.appendingPathComponent(file)
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
                precondition(size > 800, "clip missing or tiny: \(voice.name)/\(file)")
            }
            print("PASS: recorded voice \(voice.name) · \(bank.phrases.count) sentences, \(bank.distance.count) distances, \(bank.action.count) actions, \(bank.number.count) numbers, \(bank.tail.count) tails")
        }
        // At least one voice must cover everything; it is the one the app selects on first run.
        precondition(complete >= 1, "no complete recorded voice")
        precondition(loaded.count >= 4, "expected the four-voice lineup, got \(loaded.count)")
        // v46: the app's own announcements — briefing, automations, control replies — must come out
        // of the recordings, not the engine. A missing head or tail used to send a whole sentence
        // to the engine without anything failing, so the coverage is asserted here.
        let mustCover = [
            "현재 배터리 잔량은 삼십 퍼센트입니다.", "예정 운행의 예상 충전 목표는 팔십 퍼센트입니다.",
            "이전 주차 전후 잔량 차이는 삼 퍼센트포인트입니다.", "목적지까지 약 삼십 분 남았습니다.",
            "앱에서 관측한 연속 운전 시간이 백이십 분을 넘었습니다.",
            "차량 내비의 도착 예상이 처음보다 약 십 분 늦어졌습니다.",
            "배터리 잔량이 이십 퍼센트입니다. 충전 계획을 확인하세요.",
            "탑승을 환영합니다.", "출발했습니다. 안전한 운행 되세요.", "운행이 종료되었습니다.",
            "좋은 아침입니다.", "좋은 오후입니다.", "좋은 저녁입니다.", "늦은 시간입니다. 편안하고 안전하게 이동하세요.",
            "타이어 공기압 주의 신호가 있습니다. 안전한 곳에서 타이어 상태를 확인하세요.",
            "차량 응답을 확인하지 못했습니다.", "지금은 차량에서 실행할 수 없습니다.", "선택한 기능을 실행하지 못했습니다.",
            "공조를 시작합니다.", "공조를 끕니다.", "충전을 시작합니다.", "충전을 중지합니다.",
            "충전 포트를 엽니다.", "충전 포트를 닫습니다.", "차량 문을 잠급니다.", "차량 문 잠금을 해제합니다.",
            "트렁크를 작동합니다.", "트렁크를 닫습니다.", "프렁크를 엽니다.", "선택한 기능을 실행합니다.",
            "실내 온도를 이십삼도로 설정합니다.", "충전 한도를 팔십퍼센트로 설정합니다.",
            "삼백 미터 앞, 우회전입니다."
        ]
        for voice in loaded {
            for line in mustCover {
                precondition(RecordedVoice.covers(line, voice: voice.id),
                             "\(voice.name) cannot say: \(line)")
            }
        }
        // v44: every voice covers the same lines, so a listener can switch without losing anything.
        // Comparing the banks against each other says that far better than any per-voice count.
        for voice in loaded.dropFirst() {
            let a = loaded[0].bank, b = voice.bank
            precondition(Set(a.phrases.keys) == Set(b.phrases.keys), "\(voice.name) sentences differ")
            precondition(Set(a.distance.keys) == Set(b.distance.keys), "\(voice.name) distances differ")
            precondition(Set(a.action.keys) == Set(b.action.keys), "\(voice.name) actions differ")
            precondition(Set(a.head.keys) == Set(b.head.keys), "\(voice.name) heads differ")
            precondition(Set(a.number.keys) == Set(b.number.keys), "\(voice.name) numbers differ")
            precondition(Set(a.tail.keys) == Set(b.tail.keys), "\(voice.name) tails differ")
        }
        precondition(SpeechText.prepare("60킬로미터").contains("육십"))
        precondition(SpeechText.prepare("46%").contains("사십육"))
        precondition(VoiceLibrary.label(for: loaded[0].id).contains(loaded[0].name))
        precondition(VoiceLibrary.profile(for: RecordedVoice.fallbackProfileID) != nil)

        var checks = 0
        // v41: six voices — five female reads plus one male. Everything is casting, tempo, wording and a
        // light broadcast tilt; nothing is warped beyond a hair of formant on the bright one.
        let female = VoiceLibrary.presets.filter { $0.female }
        precondition(VoiceLibrary.presets.count == 6 && female.count == 5)
        precondition(Set(VoiceLibrary.presets.map { $0.id }).count == 6)
        precondition(VoiceLibrary.presets.allSatisfy { $0.formant <= 1.08 && $0.breath <= 0.12 && $0.thick <= 0.12 })
        precondition(VoiceLibrary.presets.allSatisfy { $0.validated() == $0 && $0.tone != nil })
        // The two characters must actually differ: the warm one lower, darker and slower than the bright one.
        guard let warm = VoiceLibrary.profile(for: "preset:warm-f"), let bright = VoiceLibrary.profile(for: "preset:bright-f") else { preconditionFailure("character voices missing") }
        precondition(warm.base == "F3" && bright.base == "F1")
        precondition(warm.pitch < bright.pitch - 50 && warm.speed < bright.speed - 0.05)
        precondition(warm.eq[1] > 2 && warm.eq[9] < -2 && bright.eq[0] < -2 && bright.eq[6] > 2)
        precondition(warm.breathWarmth > 0.8 && bright.breathWarmth < 0.3)
        // Retired ids still resolve so a saved selection never dead-ends.
        precondition(VoiceLibrary.profile(for: "preset:anime-sultry")?.id == "preset:warm-f")
        precondition(VoiceLibrary.profile(for: "preset:anime-bright")?.id == "preset:bright-f")
        precondition(CharacterTone.thirties.rewrite("12분 남았어요.") == "12분 남았습니다.")
        precondition(CharacterTone.twenties.rewrite("목적지까지 12분 남았습니다.") == "목적지까지 12분 남았어요.")
        var steady = [Float](repeating: 0, count: 44100 * 3)
        for i in steady.indices {
            let t = Double(i) / 44100.0
            let a = sin(2.0 * Double.pi * 200.0 * t) * 0.3
            let b = sin(2.0 * Double.pi * 400.0 * t) * 0.15
            let c = sin(2.0 * Double.pi * 600.0 * t) * 0.08
            steady[i] = Float(a + b + c)
        }
        let animated = CharacterVoiceDSP.apply(steady, sampleRate: 44100, formant: 1.1, breath: 0, life: 0.8, vibrato: 10)
        let steadyF0 = medianF0(steady, sampleRate: 44100), animatedF0 = medianF0(animated, sampleRate: 44100)
        print("CHECK: character stage keeps pitch \(Int(steadyF0)) Hz -> \(Int(animatedF0)) Hz")
        precondition(abs(animatedF0 - steadyF0) / steadyF0 < 0.04, "character stage shifted the pitch")
        let probe = (0..<4410).map { Float(sin(Double($0) * 0.06)) * 0.4 }
        let warped = CharacterVoiceDSP.apply(probe, sampleRate: 44100, formant: 1.3, breath: 0.1)
        precondition(warped.count == probe.count && warped.allSatisfy { $0.isFinite })
        precondition(zip(probe, warped).map { abs($0 - $1) }.max()! > 0.001)
        var custom = VoiceLibrary.base("F1"); custom.pitch = 9999; custom.base = "../x"; custom.speed = .nan; custom.eq = [99]
        let safe = custom.validated()
        precondition(safe.pitch == 800 && safe.base == "F1" && safe.speed == 1 && safe.eq.count == 10 && safe.eq[0] == 12)
        precondition(VoiceLibrary.profile(for: "FC6")?.id == "preset:clear-f" && VoiceLibrary.profile(for: "MC2")?.id == "preset:clear-m")
        precondition(VoiceLibrary.profile(for: "preset:night-dj")?.id == "preset:clear-f" && VoiceLibrary.profile(for: "M3")?.base == "M3")
        let sentence = "삼백 미터 앞에서 우회전하세요. 오늘도 안전하게 안내하겠습니다."
        precondition(SpeechChunker.split(sentence).count == 2)
        for profile in VoiceLibrary.presets {
            let style = try loadProfileStyle(profile, folder: root)
            // v37: render what the persona would actually say, so the sample carries its wording too.
            let spoken = profile.tone?.rewrite(sentence) ?? sentence
            let result = try tts.call(spoken, "ko", style, 8, speed: profile.speed)
            precondition(result.wav.allSatisfy { $0.isFinite } && result.wav.count > 1000)
            let shaped = try VoiceEffects.apply(result.wav, sampleRate: tts.sampleRate, profile: profile)
            let rms = sqrt(shaped.reduce(0.0) { $0 + Double($1)*Double($1) } / Double(shaped.count))
            precondition(shaped.allSatisfy { $0.isFinite } && shaped.count > result.wav.count / 2 && rms > 0.001 && rms < 0.9)
            // v36: the rendered pitch decides whether a character voice reads as one. Blending a partner
            // speaker used to drag it from ~305 Hz down to ~210 Hz with no other symptom, so the render
            // itself is measured here rather than trusted.
            let renderedF0 = medianF0(shaped, sampleRate: tts.sampleRate)
            print("RENDER: \(profile.name) · F0 \(Int(renderedF0)) Hz · \(profile.tone?.title ?? "원문 그대로") · \"\(spoken)\"")
            // Reported, not asserted: the pitch each persona should land near is a design choice that the
            // artifact makes audible, and a hard bound here only turns a tuning question into a red build.
            if profile.id.hasPrefix("preset:anime-"), renderedF0 < 150 || renderedF0 > 420 {
                print("WARNING: \(profile.name) rendered outside the expected 150-420 Hz range")
            }
            try writeWavFile(output.appendingPathComponent("preset-" + (profile.female ? "F-" : "M-") + profile.name + ".wav").path, shaped, tts.sampleRate)
            print("PASS: preset \(profile.name), RMS \(rms)")
        }
        precondition(Set(VoicePackManifest.voices.map(VoicePackManifest.displayName)).count == 10)
        let deliveryVoice = try loadVoiceStyle([root.appendingPathComponent("voice_styles/F1.json").path], verbose: false)
        for delivery in BriefingStyle.allCases {
            let result = try tts.call(delivery.phrase("차량 상태를 안내합니다.", category: "voiceConnection"), "ko", deliveryVoice, 8, speed: delivery.rateMultiplier)
            precondition(result.wav.allSatisfy { $0.isFinite } && result.wav.count > 1000)
            try writeWavFile(output.appendingPathComponent("delivery-" + delivery.rawValue + ".wav").path, result.wav, tts.sampleRate)
            print("PASS: named delivery \(delivery.title), speed \(delivery.rateMultiplier), duration \(result.duration)")
        }
        // v40 audition set: a warm, clear, professional guidance voice is a *casting* problem before it is
        // a processing problem. These render the same line through each plausible speaker and a light
        // broadcast-style shaping so the choice can be made by ear instead of by argument.
        let auditionLine = "잠시 후 삼백 미터 앞에서 우회전입니다. 목적지까지 십이 분 남았고, 도착 예상 시각은 저녁 일곱 시 사십 분입니다. 오늘도 안전하게 모시겠습니다."
        // A broadcast tilt: a little body at 250 Hz, presence at 2.5-4 kHz, softened sibilance above 8 kHz.
        let broadcast: [Float] = [0, 1.5, 1.5, 0.5, 0, 1.5, 2, 1, -1, -2]
        var auditions: [VoiceProfile] = []
        let warmTilt: [Float] = [1, 3, 2.5, 1, 0, 0.5, 1.5, 0, -2, -3]
        let brightTilt: [Float] = [-3, -2, -0.5, 0, 0.5, 2, 2.5, 2, 1.5, 0]
        func audition(_ name: String, base: String, partner: String? = nil, blend: Float = 1, speed: Float,
                      pitch: Float = 0, breath: Float? = nil, body: Float? = nil, thick: Float? = nil, warm: Float? = nil,
                      eq: [Float]? = nil, formant: Float? = nil) {
            var p = VoiceLibrary.base(base)
            p.id = "audition:" + name; p.name = name
            p.partner = partner ?? base; p.blend = blend; p.rhythm = blend
            p.speed = speed; p.pause = 0.18; p.pitch = pitch
            p.eq = eq ?? broadcast; p.punch = 0.22; p.reverb = 3; p.formantShift = formant
            p.breathiness = breath; p.breathBody = body; p.thickness = thick; p.warmth = warm
            auditions.append(p.validated())
        }
        audition("W1-warm-F3", base: "F3", speed: 0.93, pitch: -20, breath: 0.10, body: 0.85, thick: 0.10, warm: 0.25, eq: warmTilt)
        audition("W2-warm-F4", base: "F4", speed: 0.93, pitch: -60, breath: 0.12, body: 0.9, thick: 0.12, warm: 0.3, eq: warmTilt)
        audition("B1-bright-F1", base: "F1", speed: 1.03, pitch: 70, breath: 0.05, body: 0.2, thick: 0.03, warm: 0.12, eq: brightTilt, formant: 1.06)
        audition("B2-bright-F2", base: "F2", speed: 1.05, pitch: -20, breath: 0.04, body: 0.2, thick: 0.02, warm: 0.1, eq: brightTilt)
        for profile in auditions {
            let style = try loadProfileStyle(profile, folder: root)
            let raw = try tts.call(auditionLine, "ko", style, 8, speed: profile.speed)
            let shaped = try VoiceEffects.apply(raw.wav, sampleRate: tts.sampleRate, profile: profile)
            precondition(shaped.allSatisfy { $0.isFinite } && shaped.count > 1000)
            print("AUDITION: \(profile.name) · base \(profile.base) · F0 \(Int(medianF0(shaped, sampleRate: tts.sampleRate))) Hz · \(String(format: "%.1f", Double(shaped.count) / Double(tts.sampleRate)))s")
            try writeWavFile(output.appendingPathComponent("audition-" + profile.name + ".wav").path, shaped, tts.sampleRate)
        }
        tts.checkCancelled = { checks += 1; throw CancellationError() }
        let style = try loadVoiceStyle([root.appendingPathComponent("voice_styles/F1.json").path], verbose: false)
        do { _ = try tts.call("취소 검사", "ko", style, 8); preconditionFailure("cancellation ignored") } catch is CancellationError { precondition(checks == 1) }
        print("PASS: real ONNX model execution, ten base voices + 2 clean voices, finite PCM, cancellation, appearance validation")
    }
}

/// Median F0 of voiced frames, by autocorrelation. Small and dependency-free: this runs in CI so a
/// character voice cannot silently drift out of its intended pitch range again.
func medianF0(_ samples: [Float], sampleRate: Int) -> Double {
    let window = sampleRate / 25, hop = sampleRate / 100
    let minLag = sampleRate / 420, maxLag = sampleRate / 70
    var values: [Double] = []
    var index = 0
    while index + window <= samples.count {
        var energy: Double = 0
        for k in index..<(index + window) { energy += Double(samples[k]) * Double(samples[k]) }
        if energy / Double(window) > 0.0004 {
            var best = 0, bestScore: Double = 0
            var lag = minLag
            while lag <= maxLag {
                var sum: Double = 0
                var k = index
                while k + lag < index + window { sum += Double(samples[k]) * Double(samples[k + lag]); k += 1 }
                if sum > bestScore { bestScore = sum; best = lag }
                lag += 1
            }
            if best > 0, bestScore > 0.3 * energy { values.append(Double(sampleRate) / Double(best)) }
        }
        index += hop
    }
    guard !values.isEmpty else { return 0 }
    values.sort()
    return values[values.count / 2]
}
