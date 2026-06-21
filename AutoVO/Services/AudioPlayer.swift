import Foundation
import AVFoundation
import CoreAudio

/// Persistent playback graph: a single `AVAudioEngine` + `AVAudioPlayerNode` kept
/// warm so a pre-rendered cue starts the instant it is scheduled.
///
/// The player node connects to the mixer with an explicit canonical format, so the
/// only sample-rate conversion happens once at the mixer→output boundary rather
/// than per-buffer against a device-dependent format.
final class AudioPlayer: @unchecked Sendable {
    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    let canonicalFormat: AVAudioFormat
    private var currentDeviceID: UInt32?

    init(format: AVAudioFormat = AudioFormat.canonical) {
        canonicalFormat = format
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// Route output to a specific CoreAudio device by rebuilding the engine graph on
    /// the new device. Reusing one warm engine and only calling `setDeviceID` leaves
    /// the lazily-pinned mixer→output format stale (restarts into silence) and can
    /// spawn a private aggregate device; building a fresh engine and setting the
    /// device *before* touching the mixer negotiates the format cleanly. A nil
    /// `deviceID` means "system default" — we resolve the current default so selecting
    /// "System Default" actually reverts after a specific device was set. No-ops if the
    /// device is unchanged, so steady-state GO during a show never rebuilds.
    func setOutputDevice(_ deviceID: UInt32?) {
        guard let target = deviceID ?? Self.systemDefaultOutputDevice() else { return }
        guard target != currentDeviceID else { return }

        // Tear down the current graph (switching only happens between cues).
        player.stop()
        engine.stop()

        let newEngine = AVAudioEngine()
        let newPlayer = AVAudioPlayerNode()
        newEngine.attach(newPlayer)
        do {
            // Set the device on the fresh output node before the mixer is realized.
            try newEngine.outputNode.auAudioUnit.setDeviceID(target)
            currentDeviceID = target
            NSLog("[AutoVO] AudioPlayer: output routed to device id %u%@", target,
                  deviceID == nil ? " (system default)" : "")
        } catch {
            // Device likely vanished — fall back to the system default output so the
            // next cue still plays instead of failing silently.
            NSLog("[AutoVO] AudioPlayer: device id %u unavailable, using system default: %@",
                  target, String(describing: error))
            currentDeviceID = nil
        }
        newEngine.connect(newPlayer, to: newEngine.mainMixerNode, format: canonicalFormat)
        newEngine.prepare()

        engine = newEngine
        player = newPlayer
    }

    /// The system's current default output device, or nil if it can't be read.
    private static func systemDefaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return (status == noErr && deviceID != 0) ? deviceID : nil
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
