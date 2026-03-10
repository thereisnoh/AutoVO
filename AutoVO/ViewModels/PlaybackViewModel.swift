import Foundation
import AVFoundation
import SwiftUI

enum PlaybackState {
    case idle, playing, paused
}

@MainActor
final class PlaybackViewModel: ObservableObject {
    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var currentScriptID: UUID?

    // Both owned internally — TTSService and AppSettings share no global
    // mutable state that requires injection from App.
    private let tts = TTSService()
    private let settings = AppSettings()
    private var queue: [Script] = []

    init() {
        tts.onUtteranceFinished = { [weak self] in
            Task { @MainActor [weak self] in
                self?.advanceQueue()
            }
        }
    }

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
        tts.pauseSpeaking()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        tts.resumeSpeaking()
        state = .playing
    }

    func stop() {
        tts.stopSpeaking()
        state = .idle
        currentScriptID = nil
        queue = []
    }

    func skip() {
        tts.stopSpeaking()
        // Don't reset isCancelled — let advanceQueue handle next item naturally
        // We manually advance here
        let nextIndex = currentIndex + 1
        if nextIndex < queue.count {
            currentIndex = nextIndex
            playCurrentItem()
        } else {
            state = .idle
            currentScriptID = nil
        }
    }

    var totalCount: Int { queue.count }

    // MARK: - Private

    private func playCurrentItem() {
        guard currentIndex < queue.count else {
            state = .idle
            currentScriptID = nil
            return
        }
        let script = queue[currentIndex]
        currentScriptID = script.id
        state = .playing

        let voiceID = settings.selectedVoiceIdentifier.isEmpty ? nil : settings.selectedVoiceIdentifier
        let deviceID = settings.selectedAudioDeviceID

        tts.speak(text: script.body, voiceIdentifier: voiceID, outputDeviceID: deviceID)
    }

    private func advanceQueue() {
        guard state == .playing else { return }
        let nextIndex = currentIndex + 1
        if nextIndex < queue.count {
            currentIndex = nextIndex
            playCurrentItem()
        } else {
            state = .idle
            currentScriptID = nil
        }
    }
}
