import Foundation
import AppKit
import SwiftUI

@MainActor
final class ProjectViewModel: ObservableObject {
    @Published var project: Project = Project()
    @Published var fileURL: URL?
    @Published var selectedScriptID: UUID?

    /// The project as last loaded/saved. Dirtiness is derived by comparison rather
    /// than tracked by hand, so view-side change notifications can't mis-flag it.
    private var savedSnapshot: Project = Project()

    /// True when the cues differ from what is on disk (or from the blank new project).
    var isDirty: Bool { project != savedSnapshot }

    private let manager = ProjectManager()
    // Shared, injected — the single source of truth for voice/rate/device.
    private let settings: AppSettings

    /// Security-scoped bookmark of the last opened/saved project. Under the App Sandbox a
    /// plain path can't be reopened without user interaction; a bookmark can.
    private static let lastProjectBookmarkKey = "lastProjectBookmark"
    /// The URL we currently hold security-scoped access to (only set when the project
    /// was reopened from the bookmark; panel/Finder-opened URLs are already accessible).
    private var scopedAccessURL: URL?

    init(settings: AppSettings) {
        self.settings = settings
        seedBlankCueIfNeeded()
        snapshotSettingsIntoProject()
        savedSnapshot = project
    }

    // MARK: - Script CRUD

    func addScript() {
        appendBlankCue()
    }

    /// Appends a blank cue (automatic title, empty body) and selects it.
    private func appendBlankCue() {
        let script = Script()
        project.scripts.append(script)
        selectedScriptID = script.id
    }

    /// An empty project starts with one blank cue so the user can type immediately
    /// instead of clicking "+" first. Does not dirty the document.
    private func seedBlankCueIfNeeded() {
        guard project.scripts.isEmpty else { return }
        appendBlankCue()
    }

    func deleteScript(id: UUID) {
        project.scripts.removeAll { $0.id == id }
        if selectedScriptID == id {
            selectedScriptID = project.scripts.last?.id
        }
    }

    func deleteScripts(at offsets: IndexSet) {
        project.scripts.remove(atOffsets: offsets)
    }

    func moveScripts(from source: IndexSet, to destination: Int) {
        project.scripts.move(fromOffsets: source, toOffset: destination)
    }

    func updateScript(_ script: Script) {
        guard let idx = project.scripts.firstIndex(where: { $0.id == script.id }) else { return }
        project.scripts[idx] = script
    }

    func duplicateScript(id: UUID) {
        guard let idx = project.scripts.firstIndex(where: { $0.id == id }) else { return }
        // Title is kept verbatim: an automatic title stays automatic, a custom one is copied.
        var copy = project.scripts[idx]
        copy.id = UUID()
        project.scripts.insert(copy, at: idx + 1)
        selectedScriptID = copy.id
    }

    // MARK: - Document state

    /// File name without extension, or "Untitled".
    var displayName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    /// True when closing/replacing the project would lose work. Covers cue edits
    /// (`isDirty`) and the per-project voice/device, which live in `settings` until saved.
    var hasUnsavedChanges: Bool {
        isDirty
            || project.selectedVoiceIdentifier != currentVoiceForProject
            || project.selectedAudioDeviceUID != settings.selectedAudioDeviceUIDOrNil
    }

    /// Asks the user to Save / Don't Save / Cancel if there are unsaved changes.
    /// Returns true when it is safe to proceed (nothing to lose, saved, or discarded),
    /// false when the user cancelled (or cancelled the Save As panel).
    @discardableResult
    func confirmDiscardChangesIfNeeded() -> Bool {
        guard hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to “\(displayName)”?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let dontSave = alert.addButton(withTitle: "Don't Save")
        dontSave.keyEquivalent = "d"
        dontSave.keyEquivalentModifierMask = .command
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            save()
            return !hasUnsavedChanges
        case .alertThirdButtonReturn:
            return true
        default:
            return false
        }
    }

    // MARK: - File Operations

    func newProject() {
        guard confirmDiscardChangesIfNeeded() else { return }
        resetToBlankProject()
    }

    /// Called from the window's close guard (⌘W / close button). Prompts if needed and,
    /// when the close goes ahead, discards the document like a document-based app would,
    /// so a window reopened from the Dock starts clean (and reopen-last can apply).
    func prepareForWindowClose() -> Bool {
        guard confirmDiscardChangesIfNeeded() else { return false }
        resetToBlankProject()
        return true
    }

    private func resetToBlankProject() {
        endScopedAccess()
        project = Project()
        fileURL = nil
        selectedScriptID = nil
        seedBlankCueIfNeeded()
        snapshotSettingsIntoProject()
        savedSnapshot = project
    }

    /// Open a file chosen by the user or the system (Finder, Open Recent).
    func open(url: URL) {
        guard confirmDiscardChangesIfNeeded() else { return }
        load(url: url)
    }

    func openPanel() {
        guard confirmDiscardChangesIfNeeded() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(exportedAs: "com.autovo.project")]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url: url)
    }

    /// At launch, reopen the most recently used project if the setting is on and
    /// nothing else has been opened yet (e.g. via a Finder double-click).
    func reopenLastProjectIfWanted() {
        guard settings.reopenLastProject, fileURL == nil, !isDirty,
              let data = UserDefaults.standard.data(forKey: Self.lastProjectBookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &isStale),
              FileManager.default.fileExists(atPath: url.path) else {
            NSLog("[AutoVO] Last project bookmark no longer resolves; forgetting it")
            UserDefaults.standard.removeObject(forKey: Self.lastProjectBookmarkKey)
            return
        }
        beginScopedAccess(to: url)
        NSLog("[AutoVO] Reopening last project: %@%@", url.path, isStale ? " (stale bookmark, will refresh)" : "")
        load(url: url)   // on success noteProjectURL() re-saves a fresh bookmark
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
        panel.nameFieldStringValue = (fileURL?.lastPathComponent) ?? "Untitled.autovo"
        panel.directoryURL = fileURL?.deletingLastPathComponent()
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        if performSave(to: url) {
            fileURL = url
            noteProjectURL(url)
        }
    }

    // MARK: - Helpers

    private func load(url: URL) {
        if url != scopedAccessURL { endScopedAccess() }
        do {
            let loaded = try manager.load(from: url)
            project = loaded
            fileURL = url
            selectedScriptID = project.scripts.first?.id
            seedBlankCueIfNeeded()
            // Sync per-project settings
            if let voiceID = loaded.selectedVoiceIdentifier {
                settings.selectedVoiceIdentifier = voiceID
            }
            if let deviceUID = loaded.selectedAudioDeviceUID {
                settings.selectedAudioDeviceUIDOrNil = deviceUID
            }
            snapshotSettingsIntoProject()
            savedSnapshot = project
            noteProjectURL(url)
        } catch {
            presentError("The project “\(url.deletingPathExtension().lastPathComponent)” couldn't be opened.", error)
        }
    }

    @discardableResult
    private func performSave(to url: URL) -> Bool {
        snapshotSettingsIntoProject()
        do {
            try manager.save(project, to: url)
            savedSnapshot = project
            noteProjectURL(url)
            return true
        } catch {
            presentError("The project “\(url.deletingPathExtension().lastPathComponent)” couldn't be saved.", error)
            return false
        }
    }

    /// The voice as it is persisted in the project ("" in settings means nil on disk).
    private var currentVoiceForProject: String? {
        settings.selectedVoiceIdentifier.isEmpty ? nil : settings.selectedVoiceIdentifier
    }

    /// Copy the live voice/device into the project so the saved file and the
    /// unsaved-changes baseline both reflect what the user currently hears.
    private func snapshotSettingsIntoProject() {
        project.selectedVoiceIdentifier = currentVoiceForProject
        project.selectedAudioDeviceUID = settings.selectedAudioDeviceUIDOrNil
    }

    private func noteProjectURL(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.lastProjectBookmarkKey)
        } catch {
            NSLog("[AutoVO] Couldn't create bookmark for %@: %@", url.path, String(describing: error))
        }
    }

    private func beginScopedAccess(to url: URL) {
        endScopedAccess()
        if url.startAccessingSecurityScopedResource() {
            scopedAccessURL = url
        }
    }

    private func endScopedAccess() {
        scopedAccessURL?.stopAccessingSecurityScopedResource()
        scopedAccessURL = nil
    }

    private func presentError(_ title: String, _ error: Error) {
        NSLog("[AutoVO] %@ %@", title, String(describing: error))
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.runModal()
    }
}
