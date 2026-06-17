import Foundation
import AVFoundation

/// Persistent playback graph: a single `AVAudioEngine` + `AVAudioPlayerNode` kept
/// warm so a pre-rendered cue starts the instant it is scheduled.
///
/// The player node connects to the mixer with an explicit canonical format, so the
/// only sample-rate conversion happens once at the mixer→output boundary rather
/// than per-buffer against a device-dependent format.
final class AudioPlayer: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    let canonicalFormat: AVAudioFormat
    private var currentDeviceID: UInt32?

    init(format: AVAudioFormat = AudioFormat.canonical) {
        canonicalFormat = format
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// Route output to a specific CoreAudio device. Changing the device stops the
    /// engine; it restarts lazily on the next `schedule`. No-ops if already on that
    /// device or when `deviceID` is nil (system default).
    func setOutputDevice(_ deviceID: UInt32?) {
        guard let id = deviceID, id != currentDeviceID else { return }
        currentDeviceID = id
        if engine.isRunning { engine.stop() }
        do {
            try engine.outputNode.auAudioUnit.setDeviceID(id)
        } catch {
            print("AudioPlayer: failed to set output device: \(error)")
        }
    }

    func startIfNeeded() {
        guard !engine.isRunning else { return }
        do { try engine.start() } catch { print("AudioPlayer: engine start failed: \(error)") }
    }

    /// Schedule a fully-rendered cue and begin playback immediately. `completion`
    /// fires (on a background thread) after the audio has finished playing.
    func schedule(_ rendered: RenderedAudio, completion: @escaping () -> Void) {
        startIfNeeded()
        player.scheduleBuffer(rendered.buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { _ in
            completion()
        }
        if !player.isPlaying { player.play() }
    }

    func stop() {
        guard engine.isRunning else { return }
        player.stop()
    }

    func pause() {
        guard engine.isRunning else { return }
        player.pause()
    }

    func resume() {
        guard engine.isRunning else { return }
        player.play()
    }

    /// Immediate hard stop for live "panic".
    func panic() { stop() }
}
