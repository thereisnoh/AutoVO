import Foundation
import AVFoundation

/// Identity of a render: same text + voice + rate + sample rate ⇒ same audio.
/// Content-addressed, so editing a script's body yields a new key (cache miss).
struct RenderKey: Hashable {
    let text: String
    let voiceID: String?
    let rate: Float
    let sampleRate: Double
}

enum CueRenderStatus: Equatable {
    case needsRender
    case rendering
    case ready
    case failed(String)
}

/// Pre-renders cues to audio so the live engine can fire them instantly.
///
/// Owns the swappable `SpeechEngine`. Renders are content-addressed in `cache`;
/// `status` (keyed by `Script.id`) drives per-cue UI badges. A per-script
/// generation counter ensures a render superseded by an edit (`invalidate`)
/// can't clobber the newer status.
@MainActor
final class CueRenderService: ObservableObject {
    @Published private(set) var status: [UUID: CueRenderStatus] = [:]

    private let engine: SpeechEngine
    private let format: AVAudioFormat
    private var cache: [RenderKey: RenderedAudio] = [:]
    private var keyForScript: [UUID: RenderKey] = [:]
    private var inFlight: [UUID: Task<RenderedAudio?, Never>] = [:]
    private var inFlightKey: [UUID: RenderKey] = [:]
    private var generation: [UUID: Int] = [:]

    init(engine: SpeechEngine, format: AVAudioFormat = AudioFormat.canonical) {
        self.engine = engine
        self.format = format
    }

    /// Voices the active engine can render — engine-agnostic, drives the Settings
    /// picker (Kokoro speaker ids today, Apple identifiers on fallback).
    var availableVoices: [VoiceDescriptor] { engine.availableVoices }

    func key(for script: Script, settings: AppSettings) -> RenderKey {
        RenderKey(
            text: script.body,
            voiceID: settings.selectedVoiceIdentifier.isEmpty ? nil : settings.selectedVoiceIdentifier,
            rate: Float(settings.speechRate),
            sampleRate: format.sampleRate)
    }

    /// Synchronous cache lookup — non-nil means GO can fire instantly.
    func rendered(for script: Script, settings: AppSettings) -> RenderedAudio? {
        cache[key(for: script, settings: settings)]
    }

    /// Status to show for a cue: `.ready` if a current buffer is cached, else the
    /// tracked render state.
    func currentStatus(for script: Script, settings: AppSettings) -> CueRenderStatus {
        if cache[key(for: script, settings: settings)] != nil { return .ready }
        return status[script.id] ?? .needsRender
    }

    /// Render now and await the result, coalescing with an in-flight render for
    /// the same script + key. Used by the GO path on a cache miss.
    @discardableResult
    func renderNow(_ script: Script, settings: AppSettings) async -> RenderedAudio? {
        let k = key(for: script, settings: settings)
        if let hit = cache[k] {
            status[script.id] = .ready
            return hit
        }
        if let existing = inFlight[script.id], inFlightKey[script.id] == k {
            return await existing.value
        }
        return await startRender(script: script, key: k).value
    }

    /// Fire-and-forget warm of a cue (the armed cue and the one after it).
    func ensureRendered(_ script: Script, settings: AppSettings) {
        let k = key(for: script, settings: settings)
        if cache[k] != nil { status[script.id] = .ready; return }
        if inFlight[script.id] != nil, inFlightKey[script.id] == k { return }
        _ = startRender(script: script, key: k)
    }

    func warm(armed: Script?, next: Script?, settings: AppSettings) {
        if let armed { ensureRendered(armed, settings: settings) }
        if let next { ensureRendered(next, settings: settings) }
    }

    /// Mark a cue stale (its text/voice/rate changed): cancel any in-flight render
    /// and evict the cached buffer.
    func invalidate(scriptID: UUID) {
        generation[scriptID] = (generation[scriptID] ?? 0) + 1
        inFlight[scriptID]?.cancel()
        inFlight[scriptID] = nil
        inFlightKey[scriptID] = nil
        if let k = keyForScript[scriptID] {
            cache[k] = nil
            keyForScript[scriptID] = nil
        }
        status[scriptID] = .needsRender
    }

    // MARK: - Private

    private func startRender(script: Script, key k: RenderKey) -> Task<RenderedAudio?, Never> {
        inFlight[script.id]?.cancel()
        let gen = (generation[script.id] ?? 0) + 1
        generation[script.id] = gen
        status[script.id] = .rendering

        let task = Task { [weak self] () -> RenderedAudio? in
            guard let self else { return nil }
            do {
                let rendered = try await self.engine.render(
                    text: k.text, voiceID: k.voiceID, rate: k.rate, format: self.format)
                self.commit(rendered, script: script, key: k, gen: gen)
                return rendered
            } catch {
                self.fail(error, scriptID: script.id, gen: gen)
                return nil
            }
        }
        inFlight[script.id] = task
        inFlightKey[script.id] = k
        return task
    }

    private func commit(_ rendered: RenderedAudio, script: Script, key k: RenderKey, gen: Int) {
        cache[k] = rendered                       // content-addressed; safe even if superseded
        guard generation[script.id] == gen else { return }
        keyForScript[script.id] = k
        status[script.id] = .ready
        inFlight[script.id] = nil
        inFlightKey[script.id] = nil
    }

    private func fail(_ error: Error, scriptID: UUID, gen: Int) {
        guard generation[scriptID] == gen else { return }
        status[scriptID] = (error is CancellationError) ? .needsRender : .failed("\(error)")
        inFlight[scriptID] = nil
        inFlightKey[scriptID] = nil
    }
}
