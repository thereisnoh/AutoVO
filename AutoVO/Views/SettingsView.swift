import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var deviceService: AudioDeviceService

    private var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        Form {
            Section("Voice") {
                Picker("TTS Voice", selection: $settings.selectedVoiceIdentifier) {
                    Text("System Default").tag("")
                    ForEach(voices, id: \.identifier) { voice in
                        Text("\(voice.name) (\(voice.language))")
                            .tag(voice.identifier)
                    }
                }
                .pickerStyle(.menu)
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
        .frame(minWidth: 350, minHeight: 200)
        .padding()
    }
}
