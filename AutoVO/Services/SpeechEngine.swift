import Foundation
import AVFoundation

/// Quality tier of a voice, engine-agnostic.
enum VoiceQualityTier: Hashable {
    case premium, enhanced, standard
}

/// Engine-agnostic description of a voice the UI can list and select.
struct VoiceDescriptor: Identifiable, Hashable {
    let id: String          // engine-specific identifier (AVSpeechSynthesisVoice.identifier today)
    let name: String
    let language: String
    let tier: VoiceQualityTier
}

/// A fully-rendered cue: an in-memory PCM buffer in the canonical format,
/// ready to be scheduled for instant, glitch-free playback.
struct RenderedAudio: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let duration: TimeInterval
    let format: AVAudioFormat
}

enum SpeechEngineError: Error {
    case emptyText
    case synthesisFailed
    case conversionFailed
    case cancelled
}

/// A swappable speech-synthesis backend. Implementations render text fully to an
/// `AVAudioPCMBuffer` offline so the live cue engine can fire instantly. A future
/// local neural engine conforms to this same contract without touching callers.
protocol SpeechEngine: Sendable {
    var availableVoices: [VoiceDescriptor] { get }
    func defaultVoiceID(language: String) -> String?
    func render(text: String, voiceID: String?, rate: Float, format: AVAudioFormat) async throws -> RenderedAudio
}

/// The single canonical audio format used end-to-end (engine output and player
/// input) so there is no device-dependent resampling in the signal path.
enum AudioFormat {
    /// 48 kHz, stereo, deinterleaved Float32.
    static let canonical = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
}
