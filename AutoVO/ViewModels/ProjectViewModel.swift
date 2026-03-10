import Foundation
import AppKit
import SwiftUI

@MainActor
final class ProjectViewModel: ObservableObject {
    @Published var project: Project = Project()
    @Published var fileURL: URL?
    @Published var isDirty: Bool = false
    @Published var selectedScriptID: UUID?

    private let manager = ProjectManager()
    // Own AppSettings instance — backed by UserDefaults so values are always
    // in sync with the SettingsView's instance.
    private let settings = AppSettings()

    init() {}

    // MARK: - Script CRUD

    func addScript() {
        let script = Script(title: "New Script", body: "")
        project.scripts.append(script)
        selectedScriptID = script.id
        markDirty()
    }

    func deleteScript(id: UUID) {
        project.scripts.removeAll { $0.id == id }
        if selectedScriptID == id {
            selectedScriptID = project.scripts.last?.id
        }
        markDirty()
    }

    func deleteScripts(at offsets: IndexSet) {
        project.scripts.remove(atOffsets: offsets)
        markDirty()
    }

    func moveScripts(from source: IndexSet, to destination: Int) {
        project.scripts.move(fromOffsets: source, toOffset: destination)
        markDirty()
    }

    func updateScript(_ script: Script) {
        guard let idx = project.scripts.firstIndex(where: { $0.id == script.id }) else { return }
        project.scripts[idx] = script
        markDirty()
    }

    // MARK: - File Operations

    func newProject() {
        project = Project()
        fileURL = nil
        isDirty = false
        selectedScriptID = nil
    }

    func open(url: URL) {
        do {
            let loaded = try manager.load(from: url)
            project = loaded
            fileURL = url
            isDirty = false
            selectedScriptID = project.scripts.first?.id
            // Sync per-project settings
            if let voiceID = loaded.selectedVoiceIdentifier {
                settings.selectedVoiceIdentifier = voiceID
            }
            if let deviceID = loaded.selectedAudioDeviceID {
                settings.selectedAudioDeviceID = deviceID
            }
        } catch {
            print("ProjectViewModel: Failed to open \(url): \(error)")
        }
    }

    func save() {
        guard let url = fileURL else {
            saveAs()
            return
        }
        performSave(to: url)
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(exportedAs: "com.autovo.project")]
        panel.nameFieldStringValue = "Untitled.autovo"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        fileURL = url
        performSave(to: url)
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(exportedAs: "com.autovo.project")]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url: url)
    }

    // MARK: - Helpers

    var windowTitle: String {
        let name = fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        return isDirty ? "\(name) — Edited" : name
    }

    private func markDirty() {
        isDirty = true
    }

    private func performSave(to url: URL) {
        // Store per-project voice/device from settings
        project.selectedVoiceIdentifier = settings.selectedVoiceIdentifier.isEmpty ? nil : settings.selectedVoiceIdentifier
        project.selectedAudioDeviceID = settings.selectedAudioDeviceID
        do {
            try manager.save(project, to: url)
            isDirty = false
        } catch {
            print("ProjectViewModel: Save failed: \(error)")
        }
    }
}
