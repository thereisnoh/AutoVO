import SwiftUI

@main
struct AutoVOApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var deviceService = AudioDeviceService()
    @StateObject private var render: CueRenderService
    @StateObject private var projectVM: ProjectViewModel
    @StateObject private var playback: PlaybackViewModel
    @StateObject private var cueList: CueListViewModel

    init() {
        let settings = AppSettings()
        let render = CueRenderService(engine: AppleSpeechEngine())
        _settings = StateObject(wrappedValue: settings)
        _render = StateObject(wrappedValue: render)
        _projectVM = StateObject(wrappedValue: ProjectViewModel(settings: settings))
        _playback = StateObject(wrappedValue: PlaybackViewModel(settings: settings, render: render))
        _cueList = StateObject(wrappedValue: CueListViewModel(settings: settings, render: render))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(projectVM)
                .environmentObject(playback)
                .environmentObject(settings)
                .environmentObject(deviceService)
                .environmentObject(render)
                .environmentObject(cueList)
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
                .environmentObject(playback)
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
