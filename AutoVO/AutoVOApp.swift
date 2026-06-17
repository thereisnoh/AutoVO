import SwiftUI

@main
struct AutoVOApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var deviceService = AudioDeviceService()
    @StateObject private var render: CueRenderService
    @StateObject private var projectVM: ProjectViewModel
    @StateObject private var cueList: CueListViewModel

    init() {
        let settings = AppSettings()
        // Prefer the offline Kokoro neural engine; fall back to Apple's on-device
        // voices if the model bundle isn't present or fails to load.
        let engine: SpeechEngine = KokoroSpeechEngine.locateModel()
            .flatMap { try? KokoroSpeechEngine(modelDir: $0) }
            ?? AppleSpeechEngine()
        let render = CueRenderService(engine: engine)
        _settings = StateObject(wrappedValue: settings)
        _render = StateObject(wrappedValue: render)
        _projectVM = StateObject(wrappedValue: ProjectViewModel(settings: settings))
        _cueList = StateObject(wrappedValue: CueListViewModel(settings: settings, render: render))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(projectVM)
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
                .environmentObject(cueList)
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
