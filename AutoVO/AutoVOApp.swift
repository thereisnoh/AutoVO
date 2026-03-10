import SwiftUI

@main
struct AutoVOApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var deviceService = AudioDeviceService()
    @StateObject private var projectVM = ProjectViewModel()
    @StateObject private var playback = PlaybackViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(projectVM)
                .environmentObject(playback)
                .environmentObject(settings)
                .environmentObject(deviceService)
                .onOpenURL { url in
                    projectVM.open(url: url)
                }
        }
        .commands {
            AutoVOCommands(projectVM: projectVM)
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(deviceService)
        }
    }
}

struct AutoVOCommands: Commands {
    let projectVM: ProjectViewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") {
                projectVM.newProject()
            }
            .keyboardShortcut("n")

            Button("Open…") {
                projectVM.openPanel()
            }
            .keyboardShortcut("o")

            Divider()

            Button("Save") {
                projectVM.save()
            }
            .keyboardShortcut("s")

            Button("Save As…") {
                projectVM.saveAs()
            }
            .keyboardShortcut("S")
        }
    }
}
