import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var deviceService: AudioDeviceService
    @EnvironmentObject var playback: PlaybackViewModel

    @State private var showAllLanguages = false

    private var filteredVoices: [AVSpeechSynthesisVoice] {
        let all = AVSpeechSynthesisVoice.speechVoices()
        return (showAllLanguages ? all : all.filter { $0.language.hasPrefix("en") })
            .sorted { $0.name < $1.name }
    }

    private var premiumVoices: [AVSpeechSynthesisVoice] { filteredVoices.filter { $0.quality == .premium } }
    private var enhancedVoices: [AVSpeechSynthesisVoice] { filteredVoices.filter { $0.quality == .enhanced } }
    private var standardVoices: [AVSpeechSynthesisVoice] {
        filteredVoices.filter { $0.quality != .premium && $0.quality != .enhanced }
    }

    var body: some View {
        Form {
            Section("Voice") {
                Picker("TTS Voice", selection: $settings.selectedVoiceIdentifier) {
                    Text("System Default").tag("")

                    if !premiumVoices.isEmpty {
                        Divider()
                        Text("— Premium —").foregroundStyle(.secondary)
                        ForEach(premiumVoices, id: \.identifier) { voice in
                            Label {
                                Text("\(voice.name) (\(voice.language))")
                            } icon: {
                                Image(systemName: "star.fill").foregroundColor(.yellow)
                            }
                            .tag(voice.identifier)
                        }
                    }

                    if !enhancedVoices.isEmpty {
                        Divider()
                        Text("— Enhanced —").foregroundStyle(.secondary)
                        ForEach(enhancedVoices, id: \.identifier) { voice in
                            Label {
                                Text("\(voice.name) (\(voice.language))")
                            } icon: {
                                Image(systemName: "sparkles")
                            }
                            .tag(voice.identifier)
                        }
                    }

                    if !standardVoices.isEmpty {
                        Divider()
                        Text("— Standard —").foregroundStyle(.secondary)
                        ForEach(standardVoices, id: \.identifier) { voice in
                            Text("\(voice.name) (\(voice.language))")
                                .tag(voice.identifier)
                        }
                    }
                }
                .pickerStyle(.menu)

                Toggle("Show all languages", isOn: $showAllLanguages)
                    .toggleStyle(.checkbox)

                Button("Preview Voice") {
                    let preview = Script(title: "Preview", body: "The quick brown fox jumps over the lazy dog.")
                    playback.playOne(script: preview)
                }
            }

            Section("Playback Speed") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Slower")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.speechRate, in: 0.2...0.9)
                        Text("Faster")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(rateLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("Audio Output") {
                Picker("Output Device", selection: Binding(
                    get: { settings.selectedAudioDeviceID ?? 0 },
                    set: { settings.selectedAudioDeviceID = $0 == 0 ? nil : $0 }
                )) {
                    Text("System Default").tag(UInt32(0))
                    ForEach(deviceService.outputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .pickerStyle(.menu)

                Button("Refresh Devices") {
                    deviceService.refresh()
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 380, minHeight: 260)
        .padding()
    }

    private var rateLabel: String {
        let pct = Int((settings.speechRate / 0.52) * 100)
        return "\(pct)% of default speed"
    }
}
