import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var deviceService: AudioDeviceService
    @EnvironmentObject var render: CueRenderService
    @EnvironmentObject var cueList: CueListViewModel

    /// Engine voices grouped by language, sorted for a stable menu.
    private var voiceGroups: [(language: String, voices: [VoiceDescriptor])] {
        Dictionary(grouping: render.availableVoices, by: \.language)
            .map { (language: $0.key, voices: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.language < $1.language }
    }

    var body: some View {
        Form {
            Section("Voice") {
                Picker("Voice", selection: $settings.selectedVoiceIdentifier) {
                    Text("Default").tag("")
                    ForEach(voiceGroups, id: \.language) { group in
                        Divider()
                        Text(languageLabel(group.language)).foregroundStyle(.secondary)
                        ForEach(group.voices) { voice in
                            Text(voice.name).tag(voice.id)
                        }
                    }
                }
                .pickerStyle(.menu)

                Button("Preview Voice") {
                    let preview = Script(title: "Preview", body: "The quick brown fox jumps over the lazy dog.")
                    cueList.preview(preview)
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

    private func languageLabel(_ code: String) -> String {
        switch code {
        case "en-US": return "American English"
        case "en-GB": return "British English"
        default:
            return Locale.current.localizedString(forIdentifier: code) ?? code
        }
    }

    private var rateLabel: String {
        let pct = Int((settings.speechRate / 0.52) * 100)
        return "\(pct)% of default speed"
    }
}
