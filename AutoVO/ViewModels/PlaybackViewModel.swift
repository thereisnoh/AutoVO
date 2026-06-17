import Foundation
import AVFoundation
import SwiftUI

enum PlaybackState {
    case idle, playing, paused
}

/// Sequential playback over a queue of scripts.
///
/// Each item is rendered to a complete `RenderedAudio` buffer by the swappable
/// `SpeechEngine`, then scheduled on a warm `AudioPlayer`. `epoch` is bumped on
/// every play/stop/skip so a stale async render or finished-buffer callback from
/// a previous item is ignored. (The QLab cue model in M3 supersedes this VM.)
@MainActor
final class PlaybackViewModel: ObservableObject {
    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var currentScriptID: UUID?

    private let engine: SpeechEngine = AppleSpeechEngine()
    private let player = AudioPlayer()
    private let settings = AppSettings()
    private var queue: [Script] = []

    private var epoch = 0
    private var renderTask: Task<Void, Never>?

    var totalCount: Int { queue.count }

    // MARK: - Public API

    func playAll(scripts: [Script]) {
        guard !scripts.isEmpty else { return }
        queue = scripts
        currentIndex = 0
        playCurrentItem()
    }

    func playOne(script: Script) {
        queue = [script]
        currentIndex = 0
        playCurrentItem()
    }

    func pause() {
        guard state == .playing else { return }
        player.pause()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        player.resume()
        state = .playing
    }

    func stop() {
        epoch &+= 1
        renderTask?.cancel()
        player.stop()
        state = .idle
        currentScriptID = nil
        queue = []
    }

    func skip() {
        guard !queue.isEmpty else { return }
        epoch &+= 1
        renderTask?.cancel()
        player.stop()
        let next = currentIndex + 1
        if next < queue.count {
            currentIndex = next
            playCurrentItem()
        } else {
            finish()
        }
    }

    // MARK: - Private

    private func playCurrentItem() {
        guard currentIndex < queue.count else { finish(); return }
        let script = queue[currentIndex]
        currentScriptID = script.id
        state = .playing

        epoch &+= 1
        let myEpoch = epoch

        let voiceID = settings.selectedVoiceIdentifier.isEmpty ? nil : settings.selectedVoiceIdentifier
        let rate = Float(settings.speechRate)
        player.setOutputDevice(settings.selectedAudioDeviceID)

        renderTask?.cancel()
        renderTask = Task { [weak self] in
            guard let self else { return }
            do {
                let rendered = try await self.engine.render(
                    text: script.body, voiceID: voiceID, rate: rate, format: AudioFormat.canonical)
                if Task.isCancelled { return }
                self.handleRendered(rendered, epoch: myEpoch)
            } catch {
                self.handleRenderFailure(epoch: myEpoch)
            }
        }
    }

    private func handleRendered(_ rendered: RenderedAudio, epoch myEpoch: Int) {
        guard epoch == myEpoch, state == .playing else { return }
        player.schedule(rendered) { [weak self] in
            Task { @MainActor in
                guard let self, self.epoch == myEpoch else { return }
                self.advanceQueue()
            }
        }
    }

    private func handleRenderFailure(epoch myEpoch: Int) {
        guard epoch == myEpoch else { return }
        advanceQueue()   // skip the item that failed to render
    }

    private func advanceQueue() {
        guard state == .playing else { return }
        let next = currentIndex + 1
        if next < queue.count {
            currentIndex = next
            playCurrentItem()
        } else {
            finish()
        }
    }

    private func finish() {
        player.stop()
        state = .idle
        currentScriptID = nil
    }
}
