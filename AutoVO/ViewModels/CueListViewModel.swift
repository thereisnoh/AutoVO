import Foundation
import AVFoundation
import SwiftUI

enum ShowState: Equatable {
    case standby   // a cue is armed and ready; nothing playing
    case firing    // GO pressed on a cold cue; rendering before playback
    case playing
    case paused
    case stopped   // panicked / nothing armed
}

/// QLab-style cue list. One cue is "armed" (standby); GO fires it from its
/// pre-rendered buffer for an instant start, then the standby auto-advances to
/// the next cue — it does NOT auto-fire. Stop/panic halts immediately and leaves
/// the armed cue in place so the operator can re-fire.
@MainActor
final class CueListViewModel: ObservableObject {
    @Published private(set) var cues: [Script] = []
    @Published private(set) var state: ShowState = .standby
    @Published var armedCueID: UUID?
    @Published private(set) var playingCueID: UUID?
    @Published private(set) var firedCueIDs: Set<UUID> = []
    @Published var stopAfterArmed = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private let settings: AppSettings
    private let render: CueRenderService
    private let player = AudioPlayer()

    private var epoch = 0
    private var goTask: Task<Void, Never>?
    private var timer: Timer?
    private var playStart: Date?

    init(settings: AppSettings, render: CueRenderService) {
        self.settings = settings
        self.render = render
    }

    // MARK: - Derived

    var armedIndex: Int? { armedCueID.flatMap { id in cues.firstIndex { $0.id == id } } }
    var armedCue: Script? { armedIndex.map { cues[$0] } }
    var remaining: TimeInterval { max(0, duration - elapsed) }

    // MARK: - Cue-list sync

    /// Mirror the project's scripts as the show's cue list, keeping the armed cue
    /// valid and warming it.
    func setCues(_ scripts: [Script]) {
        cues = scripts
        if let id = armedCueID, !scripts.contains(where: { $0.id == id }) {
            armedCueID = scripts.first?.id
        } else if armedCueID == nil {
            armedCueID = scripts.first?.id
        }
        firedCueIDs.formIntersection(scripts.map(\.id))
        warmArmed()
    }

    // MARK: - Arming

    func arm(_ id: UUID) {
        guard cues.contains(where: { $0.id == id }) else { return }
        armedCueID = id
        warmArmed()
    }

    func armNext() { moveArm(by: 1) }
    func armPrevious() { moveArm(by: -1) }

    private func moveArm(by delta: Int) {
        guard !cues.isEmpty else { return }
        let current = armedIndex ?? (delta > 0 ? -1 : cues.count)
        let target = max(0, min(cues.count - 1, current + delta))
        armedCueID = cues[target].id
        warmArmed()
    }

    private func warmArmed() {
        guard let i = armedIndex else { return }
        let next = (i + 1 < cues.count) ? cues[i + 1] : nil
        render.warm(armed: cues[i], next: next, settings: settings)
    }

    // MARK: - GO

    func go() {
        guard state != .firing, let cue = armedCue else { return }
        epoch &+= 1
        let myEpoch = epoch
        player.setOutputDevice(settings.selectedAudioDeviceID)

        // Instant path: the cue is already rendered.
        if let rendered = render.rendered(for: cue, settings: settings) {
            startPlayback(rendered, cue: cue, epoch: myEpoch)
            return
        }
        // Cold cue: render on demand behind a brief "firing" state.
        state = .firing
        goTask?.cancel()
        goTask = Task { [weak self] in
            guard let self else { return }
            let rendered = await self.render.renderNow(cue, settings: self.settings)
            guard !Task.isCancelled, self.epoch == myEpoch else { return }
            if let rendered {
                self.startPlayback(rendered, cue: cue, epoch: myEpoch)
            } else {
                self.state = .stopped
            }
        }
    }

    private func startPlayback(_ rendered: RenderedAudio, cue: Script, epoch myEpoch: Int) {
        playingCueID = cue.id
        duration = rendered.duration
        elapsed = 0
        state = .playing
        startTimer()
        player.schedule(rendered) { [weak self] in
            Task { @MainActor in
                guard let self, self.epoch == myEpoch else { return }
                self.onCueFinished(cueID: cue.id)
            }
        }
        // Cue-ahead: warm the cue after this one.
        if let i = cues.firstIndex(where: { $0.id == cue.id }), i + 1 < cues.count {
            render.ensureRendered(cues[i + 1], settings: settings)
        }
    }

    private func onCueFinished(cueID: UUID) {
        stopTimer()
        firedCueIDs.insert(cueID)
        playingCueID = nil
        elapsed = duration
        if stopAfterArmed {
            state = .stopped
            return
        }
        advanceArm(after: cueID)
        state = .standby
    }

    private func advanceArm(after cueID: UUID) {
        guard let i = cues.firstIndex(where: { $0.id == cueID }), i + 1 < cues.count else {
            return  // reached the end; leave the armed cue where it is
        }
        armedCueID = cues[i + 1].id
        warmArmed()
    }

    // MARK: - Transport

    func pause() {
        guard state == .playing else { return }
        player.pause()
        stopTimer()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        player.resume()
        startTimer()
        state = .playing
    }

    func stop() { panic() }

    /// Immediate hard stop. Keeps the armed cue so the operator can re-fire.
    func panic() {
        epoch &+= 1
        goTask?.cancel()
        player.panic()
        stopTimer()
        playingCueID = nil
        elapsed = 0
        duration = 0
        state = .standby
    }

    func toggleStopAfter() { stopAfterArmed.toggle() }

    /// Clear fired markers and arm the first cue (start of a run).
    func resetShow() {
        panic()
        firedCueIDs.removeAll()
        armedCueID = cues.first?.id
        warmArmed()
    }

    // MARK: - Elapsed/remaining timer

    private func startTimer() {
        playStart = Date().addingTimeInterval(-elapsed)
        timer?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let start = playStart else { return }
        elapsed = min(duration, Date().timeIntervalSince(start))
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
