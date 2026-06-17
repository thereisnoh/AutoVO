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
                    do {
                        continuation.resume(returning: try Self.assemble(chunks, format: format))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                if let converted = Self.convert(pcm, to: format) {
                    chunks.append(converted)
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

    // MARK: - Buffer assembly

    /// Convert one synthesizer buffer to the canonical format. Returns the input
    /// unchanged when it already matches.
    private static func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard capacity > 0, let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inStatus in
            if consumed { inStatus.pointee = .endOfStream; return nil }
            consumed = true
            inStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
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
