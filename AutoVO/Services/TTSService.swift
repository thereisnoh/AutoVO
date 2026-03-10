import Foundation
import AVFoundation

// Not @MainActor: the write() callback fires on a background thread and
// needs to access engine/playerNode directly without actor-hopping.
final class TTSService: NSObject, @unchecked Sendable, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    // Accessed from both main thread and write() callback thread — using
    // a simple volatile-like pattern is sufficient here (worst case: one
    // extra buffer gets scheduled after cancel, which is harmless).
    private var isCancelled: Bool = false

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
        let mainMixer = audioEngine.mainMixerNode
        let outputFormat = mainMixer.outputFormat(forBus: 0)
        audioEngine.connect(playerNode, to: mainMixer, format: outputFormat)
    }

    func setOutputDevice(_ deviceID: UInt32) {
        do {
            if audioEngine.isRunning { audioEngine.stop() }
            try audioEngine.outputNode.auAudioUnit.setDeviceID(deviceID)
        } catch {
            print("TTSService: Failed to set output device: \(error)")
        }
    }

    func speak(text: String, voiceIdentifier: String?, outputDeviceID: UInt32?) {
        stopSpeaking()
        isCancelled = false

        if let deviceID = outputDeviceID {
            setOutputDevice(deviceID)
        }

        let utterance = AVSpeechUtterance(string: text)
        if let voiceID = voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

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
            if let convertedBuffer = self.convert(buffer: pcmBuffer, to: targetFormat) {
                self.playerNode.scheduleBuffer(convertedBuffer, completionHandler: nil)
            } else {
                self.playerNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
            }
        }
    }

    private func convert(buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard buffer.format != targetFormat,
              let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else { return nil }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 512
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else { return nil }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        if status == .error { return nil }
        return outputBuffer
    }

    func stopSpeaking() {
        isCancelled = true
        synthesizer.stopSpeaking(at: .immediate)
        playerNode.stop()
        playerNode.play()
    }

    func pauseSpeaking() {
        synthesizer.pauseSpeaking(at: .word)
        playerNode.pause()
    }

    func resumeSpeaking() {
        synthesizer.continueSpeaking()
        playerNode.play()
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }
    var isPaused: Bool { synthesizer.isPaused }
}

extension TTSService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Handled via write() zero-length buffer callback
    }
}
