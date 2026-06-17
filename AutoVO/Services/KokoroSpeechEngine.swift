import Foundation
import AVFoundation

/// `SpeechEngine` backed by **Kokoro** (82M-parameter neural TTS) running fully
/// offline, in-process, via the vendored sherpa-onnx static xcframework
/// (onnxruntime + espeak-ng baked in). Kokoro emits 24 kHz mono float audio,
/// which we resample once to the canonical 48 kHz stereo signal path.
///
/// Not `@MainActor`: synthesis is CPU-heavy and runs on a private serial queue
/// (the native `tts` handle is used from that queue only). `@unchecked Sendable`
/// for the same reason — the opaque pointer never escapes the queue.
final class KokoroSpeechEngine: SpeechEngine, @unchecked Sendable {
    private let tts: OpaquePointer
    private let nativeSampleRate: Double
    private let speakerCount: Int
    private let queue = DispatchQueue(label: "com.autovo.kokoro.tts")

    /// Locate the Kokoro model directory. Prefers a copy bundled into the app
    /// (`kokoro/` under Resources, added in the bundling milestone); falls back to
    /// the repo's `Vendor/kokoro` for dev builds before bundling exists.
    static func locateModel() -> URL? {
        if let bundled = Bundle.main.url(forResource: "kokoro", withExtension: nil),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("model.onnx").path) {
            return bundled
        }
        // Dev fallback: walk up from the executable to the repo's Vendor/kokoro.
        let dev = URL(fileURLWithPath: "/Users/jon/Dev/AutoVO/Vendor/kokoro")
        if FileManager.default.fileExists(atPath: dev.appendingPathComponent("model.onnx").path) {
            return dev
        }
        return nil
    }

    /// Create the engine from a Kokoro model directory containing `model.onnx`,
    /// `voices.bin`, `tokens.txt`, and `espeak-ng-data/`. Throws if the model is
    /// missing or the native handle can't be created.
    init(modelDir: URL, numThreads: Int32 = 4) throws {
        let model = modelDir.appendingPathComponent("model.onnx").path
        let voices = modelDir.appendingPathComponent("voices.bin").path
        let tokens = modelDir.appendingPathComponent("tokens.txt").path
        let dataDir = modelDir.appendingPathComponent("espeak-ng-data").path
        let lexicon = modelDir.appendingPathComponent("lexicon-us-en.txt").path

        let fm = FileManager.default
        guard fm.fileExists(atPath: model), fm.fileExists(atPath: voices),
              fm.fileExists(atPath: tokens), fm.fileExists(atPath: dataDir) else {
            throw SpeechEngineError.synthesisFailed
        }

        // strdup the config strings; sherpa copies them during create, so we free
        // immediately after. Zero-initialised config leaves vits/matcha/kitten
        // sub-configs null → only the Kokoro path is active. The multi-lingual
        // Kokoro v1.0 model requires a `lang` (and benefits from a `lexicon`),
        // else CreateOfflineTts fails.
        let cModel = strdup(model), cVoices = strdup(voices)
        let cTokens = strdup(tokens), cDataDir = strdup(dataDir)
        let cLexicon = fm.fileExists(atPath: lexicon) ? strdup(lexicon) : nil
        let cLang = strdup("en")
        let cProvider = strdup("cpu")
        defer {
            free(cModel); free(cVoices); free(cTokens); free(cDataDir)
            free(cLexicon); free(cLang); free(cProvider)
        }

        var config = SherpaOnnxOfflineTtsConfig()
        config.model.kokoro.model = UnsafePointer(cModel)
        config.model.kokoro.voices = UnsafePointer(cVoices)
        config.model.kokoro.tokens = UnsafePointer(cTokens)
        config.model.kokoro.data_dir = UnsafePointer(cDataDir)
        config.model.kokoro.lexicon = cLexicon.map { UnsafePointer($0) }
        config.model.kokoro.lang = UnsafePointer(cLang)
        config.model.kokoro.length_scale = 1.0
        config.model.num_threads = numThreads
        config.model.provider = UnsafePointer(cProvider)
        config.model.debug = 0
        config.max_num_sentences = 2
        config.silence_scale = 0.2

        guard let handle = SherpaOnnxCreateOfflineTts(&config) else {
            throw SpeechEngineError.synthesisFailed
        }
        self.tts = handle
        self.nativeSampleRate = Double(SherpaOnnxOfflineTtsSampleRate(handle))
        self.speakerCount = max(1, Int(SherpaOnnxOfflineTtsNumSpeakers(handle)))
    }

    deinit { SherpaOnnxDestroyOfflineTts(tts) }

    // MARK: - SpeechEngine

    /// English Kokoro voices (US + UK) exposed as descriptors. The non-English
    /// voices in the multi-lingual model are omitted because we phonemize with a
    /// fixed `lang = "en"`; surfacing them would mislead.
    var availableVoices: [VoiceDescriptor] {
        (0..<min(speakerCount, Self.voiceKeys.count)).compactMap { sid in
            let key = Self.voiceKeys[sid]
            guard key.hasPrefix("a") || key.hasPrefix("b") else { return nil }
            return VoiceDescriptor(id: String(sid), name: Self.displayName(key),
                                   language: Self.language(key), tier: .premium)
        }
    }

    func defaultVoiceID(language: String) -> String? { String(Self.defaultSpeakerID) }

    /// `af_heart` — Kokoro's flagship voice; used when no voice is selected.
    static let defaultSpeakerID = 3

    /// Ordered Kokoro v1.0 voice keys (array index == speaker id), taken from the
    /// model's `id2speaker` metadata.
    private static let voiceKeys: [String] = [
        "af_alloy", "af_aoede", "af_bella", "af_heart", "af_jessica", "af_kore",
        "af_nicole", "af_nova", "af_river", "af_sarah", "af_sky",
        "am_adam", "am_echo", "am_eric", "am_fenrir", "am_liam", "am_michael",
        "am_onyx", "am_puck", "am_santa",
        "bf_alice", "bf_emma", "bf_isabella", "bf_lily",
        "bm_daniel", "bm_fable", "bm_george", "bm_lewis",
        "ef_dora", "em_alex", "ff_siwis", "hf_alpha", "hf_beta", "hm_omega",
        "hm_psi", "if_sara", "im_nicola", "jf_alpha", "jf_gongitsune", "jf_nezumi",
        "jf_tebukuro", "jm_kumo", "pf_dora", "pm_alex", "pm_santa",
        "zf_xiaobei", "zf_xiaoni", "zf_xiaoxiao", "zf_xiaoyi",
        "zm_yunjian", "zm_yunxi", "zm_yunxia", "zm_yunyang"
    ]

    /// "af_heart" → "Heart (F)". Gender comes from the second character.
    private static func displayName(_ key: String) -> String {
        let base = key.split(separator: "_").last.map(String.init) ?? key
        let name = base.prefix(1).uppercased() + base.dropFirst()
        let gender = key.count > 1 && key[key.index(key.startIndex, offsetBy: 1)] == "f" ? "F" : "M"
        return "\(name) (\(gender))"
    }

    private static func language(_ key: String) -> String {
        key.hasPrefix("b") ? "en-GB" : "en-US"
    }

    func render(text: String, voiceID: String?, rate: Float, format: AVAudioFormat) async throws -> RenderedAudio {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SpeechEngineError.emptyText }

        let requested = voiceID.flatMap { Int($0) } ?? Self.defaultSpeakerID
        let sid = Int32(max(0, min(requested, speakerCount - 1)))
        let speed = Self.speed(forRate: rate)

        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    continuation.resume(returning: try generateSync(trimmed, sid: sid, speed: speed, format: format))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Native generation (serial queue only)

    private func generateSync(_ text: String, sid: Int32, speed: Float, format: AVAudioFormat) throws -> RenderedAudio {
        var gen = SherpaOnnxGenerationConfig()
        gen.speed = speed
        gen.sid = sid
        gen.silence_scale = 0.2

        let audioPtr = text.withCString { c in
            SherpaOnnxOfflineTtsGenerateWithConfig(tts, c, &gen, nil, nil)
        }
        guard let audio = audioPtr else { throw SpeechEngineError.synthesisFailed }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }

        let n = Int(audio.pointee.n)
        let sr = Double(audio.pointee.sample_rate)
        guard n > 0, sr > 0, let samples = audio.pointee.samples,
              let srcFormat = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let srcBuf = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: AVAudioFrameCount(n)),
              let dst = srcBuf.floatChannelData else {
            throw SpeechEngineError.synthesisFailed
        }
        dst[0].update(from: samples, count: n)   // copy off the native buffer before it's freed
        srcBuf.frameLength = AVAudioFrameCount(n)

        let out = try Self.resample(srcBuf, to: format)
        return RenderedAudio(buffer: out, duration: Double(out.frameLength) / format.sampleRate, format: format)
    }

    // MARK: - Helpers

    /// Map the speech-rate slider (≈0.2…0.9, where 0.52 ≈ normal) to Kokoro's
    /// `speed` multiplier (1.0 = normal, >1 faster), clamped to a sane range.
    private static func speed(forRate rate: Float) -> Float {
        guard rate > 0 else { return 1.0 }
        return min(max(rate / 0.52, 0.5), 2.0)
    }

    /// One-shot resample of a complete buffer to the target format (24 kHz mono →
    /// 48 kHz stereo). A single converter + single feed-then-endOfStream pass
    /// drains the whole utterance, including the resampler tail.
    private static func resample(_ input: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        if input.format == format { return input }
        guard let converter = AVAudioConverter(from: input.format, to: format) else {
            throw SpeechEngineError.conversionFailed
        }
        converter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue

        let ratio = format.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw SpeechEngineError.conversionFailed
        }

        var fed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inStatus in
            if fed { inStatus.pointee = .endOfStream; return nil }
            fed = true
            inStatus.pointee = .haveData
            return input
        }
        guard status != .error, output.frameLength > 0 else {
            throw SpeechEngineError.conversionFailed
        }
        return output
    }
}
