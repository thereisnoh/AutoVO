import Foundation
import AVFoundation

@MainActor
final class TTSService: NSObject, ObservableObject {
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

        // Use write() to capture PCM buffers and play via AVAudioEngine
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
                // Utterance complete
                DispatchQueue.main.async {
                    self.onUtteranceFinished?()
                }
                return
            }

            // Convert buffer format if needed
            if let convertedBuffer = self.convert(buffer: pcmBuffer, to: self.audioEngine.mainMixerNode.outputFormat(forBus: 0)) {
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
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Handled via write() zero-length buffer callback
    }
}
