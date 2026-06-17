import Foundation
import AVFoundation

/// `SpeechEngine` backed by Apple's on-device `AVSpeechSynthesizer`.
///
/// Not `@MainActor`: `AVSpeechSynthesizer.write(_:)` delivers its buffer callback
/// on a background thread. Each `render` uses a fresh synthesizer so concurrent
/// renders (e.g. warming the armed + next cue) don't collide; the synthesizer is
/// retained in `active` until its write completes.
final class AppleSpeechEngine: SpeechEngine, @unchecked Sendable {
    private var active = Set<AVSpeechSynthesizer>()
    private let lock = NSLock()

    var availableVoices: [VoiceDescriptor] {
        AVSpeechSynthesisVoice.speechVoices().map {
            VoiceDescriptor(id: $0.identifier, name: $0.name, language: $0.language, tier: Self.tier($0.quality))
        }
    }

    func defaultVoiceID(language: String) -> String? {
        Self.bestVoice(language: language)?.identifier
    }

    func render(text: String, voiceID: String?, rate: Float, format: AVAudioFormat) async throws -> RenderedAudio {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpeechEngineError.emptyText
        }

        let synth = AVSpeechSynthesizer()
        lock.withLock { _ = active.insert(synth) }

        return try await withCheckedThrowingContinuation { continuation in
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voiceID.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
                ?? Self.bestVoice(language: "en-US")
            utterance.rate = rate

            // A SINGLE converter is reused for every buffer of this utterance, so
            // sample-rate conversion is continuous (no per-buffer filter reset,
            // which is what caused boundary clicks/crackle).
            var converter: AVAudioConverter?
            var chunks: [AVAudioPCMBuffer] = []
            var finished = false

            synth.write(utterance) { [weak self] buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }

                // Zero-length buffer signals the utterance is complete.
                if pcm.frameLength == 0 {
                    guard !finished else { return }
                    finished = true
                    if let self {
                        self.lock.withLock { _ = self.active.remove(synth) }
                    }
                    if let converter, let tail = Self.drain(converter, to: format) {
                        chunks.append(tail)   // flush the resampler's remaining samples
                    }
                    do {
                        continuation.resume(returning: try Self.assemble(chunks, format: format))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                // Already canonical (rare) — copy and keep, no conversion.
                if pcm.format == format {
                    if let copy = Self.copy(pcm) { chunks.append(copy) }
                    return
                }

                if converter == nil {
                    let made = AVAudioConverter(from: pcm.format, to: format)
                    made?.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering
                    made?.sampleRateConverterQuality = AVAudioQuality.max.rawValue
                    converter = made
                }
                if let converter, let out = Self.feed(pcm, through: converter, to: format) {
                    chunks.append(out)
                }
            }
        }
    }

    // MARK: - Voice helpers

    private static func tier(_ q: AVSpeechSynthesisVoiceQuality) -> VoiceQualityTier {
        switch q {
        case .premium: return .premium
        case .enhanced: return .enhanced
        default: return .standard
        }
    }

    private static func bestVoice(language: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language) }
        if let premium = voices.first(where: { $0.quality == .premium }) { return premium }
        if let enhanced = voices.first(where: { $0.quality == .enhanced }) { return enhanced }
        return AVSpeechSynthesisVoice(language: language)
    }

    // MARK: - Continuous resampling

    /// Feed one input buffer through the shared converter WITHOUT flushing, so the
    /// resampler keeps its filter state across buffer boundaries.
    private static func feed(_ input: AVAudioPCMBuffer, through converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var provided = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inStatus in
            if provided { inStatus.pointee = .noDataNow; return nil }
            provided = true
            inStatus.pointee = .haveData
            return input
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }

    /// Flush the converter's remaining (held-back) samples at end of stream.
    private static func drain(_ converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { return nil }
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inStatus in
            inStatus.pointee = .endOfStream
            return nil
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }

    /// Deep-copy a canonical (float, non-interleaved) buffer to retain it past the
    /// synthesizer callback.
    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let out = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
              let src = buffer.floatChannelData, let dst = out.floatChannelData else { return nil }
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        for ch in 0..<channels {
            dst[ch].update(from: src[ch], count: frames)
        }
        out.frameLength = buffer.frameLength
        return out
    }

    /// Concatenate canonical-format chunks into a single buffer + its duration.
    private static func assemble(_ chunks: [AVAudioPCMBuffer], format: AVAudioFormat) throws -> RenderedAudio {
        let total = chunks.reduce(AVAudioFrameCount(0)) { $0 + $1.frameLength }
        guard total > 0, let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total) else {
            throw SpeechEngineError.synthesisFailed
        }
        let channels = Int(format.channelCount)
        var offset = 0
        for chunk in chunks {
            guard let src = chunk.floatChannelData, let dst = out.floatChannelData else { continue }
            let frames = Int(chunk.frameLength)
            for ch in 0..<channels {
                dst[ch].advanced(by: offset).update(from: src[ch], count: frames)
            }
            offset += frames
        }
        out.frameLength = total
        return RenderedAudio(buffer: out, duration: Double(total) / format.sampleRate, format: format)
    }
}
