import Foundation
import AVFoundation

// Not @MainActor: AVSpeechSynthesizer.write() fires its buffer callback on
// a background thread, so actor isolation would be violated there.
final class TTSService: NSObject, @unchecked Sendable, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var isCancelled = false

    var onUtteranceFinished: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
        setupEngine()
    }

    private func setupEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        audioEngine.attach(playerNode)
        // Use nil format so AVAudioEngine picks the appropriate conversion
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: nil)
    }

    func setOutputDevice(_ deviceID: UInt32) {
        if audioEngine.isRunning { audioEngine.stop() }
        do {
            try audioEngine.outputNode.auAudioUnit.setDeviceID(deviceID)
        } catch {
            print("TTSService: Failed to set output device: \(error)")
        }
    }

    func speak(text: String, voiceIdentifier: String?, outputDeviceID: UInt32?, rate: Float = AVSpeechUtteranceDefaultSpeechRate) {
        // Cancel any in-flight write() callback and stop the synthesizer.
        // Do NOT touch playerNode here — engine may not be running yet.
        isCancelled = true
        synthesizer.stopSpeaking(at: .immediate)
        if audioEngine.isRunning { playerNode.stop() }
        isCancelled = false

        if let deviceID = outputDeviceID {
            setOutputDevice(deviceID) // stops engine if it was running
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voiceIdentifier.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
            ?? bestAvailableVoice(language: "en-US")
        utterance.rate = rate

        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                print("TTSService: Engine start failed: \(error)")
                return
            }
        }
        playerNode.play()

        synthesizer.write(utterance) { [weak self] buffer in
            guard let self, !self.isCancelled else { return }
            guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }

            if pcmBuffer.frameLength == 0 {
                // Zero-length buffer signals utterance complete
                DispatchQueue.main.async { [weak self] in
                    self?.onUtteranceFinished?()
                }
                return
            }

            let targetFormat = self.audioEngine.mainMixerNode.outputFormat(forBus: 0)
            if let converted = self.convert(buffer: pcmBuffer, to: targetFormat) {
                self.playerNode.scheduleBuffer(converted, completionHandler: nil)
            } else {
                self.playerNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
            }
        }
    }

    func stopSpeaking() {
        isCancelled = true
        synthesizer.stopSpeaking(at: .immediate)
        guard audioEngine.isRunning else { return }
        playerNode.stop()
    }

    func pauseSpeaking() {
        synthesizer.pauseSpeaking(at: .word)
        guard audioEngine.isRunning else { return }
        playerNode.pause()
    }

    func resumeSpeaking() {
        synthesizer.continueSpeaking()
        guard audioEngine.isRunning else { return }
        playerNode.play()
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }
    var isPaused: Bool { synthesizer.isPaused }

    // MARK: - Private

    private func bestAvailableVoice(language: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language) }
        // Prefer premium → enhanced → default
        if let premium = voices.first(where: { $0.quality == .premium }) { return premium }
        if let enhanced = voices.first(where: { $0.quality == .enhanced }) { return enhanced }
        return AVSpeechSynthesisVoice(language: language)
    }

    private func convert(buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard buffer.format != targetFormat,
              let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else { return nil }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 512
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }

        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        return status == .error ? nil : output
    }
}

extension TTSService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Handled via write() zero-length buffer callback
    }
}
