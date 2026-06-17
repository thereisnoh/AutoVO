import SwiftUI

struct ContentView: View {
    @EnvironmentObject var projectVM: ProjectViewModel
    @EnvironmentObject var playback: PlaybackViewModel
    @EnvironmentObject var render: CueRenderService

    enum Mode { case edit, show }
    @State private var mode: Mode = .edit

    var body: some View {
        switch mode {
        case .edit: editView
        case .show: ShowModeView(mode: $mode)
        }
    }

    private var editView: some View {
        NavigationSplitView {
            ScriptListView(playback: playback)
                .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        } detail: {
            if let selectedID = projectVM.selectedScriptID,
               let idx = projectVM.project.scripts.firstIndex(where: { $0.id == selectedID }) {
                ScriptEditorView(script: $projectVM.project.scripts[idx])
                    .onChange(of: projectVM.project.scripts[idx]) { _ in
                        projectVM.isDirty = true
                        render.invalidate(scriptID: selectedID)
                    }
            } else {
                emptyState
            }
        }
        .safeAreaInset(edge: .bottom) {
            PlaybackControlsView(playback: playback)
        }
        .navigationTitle(projectVM.windowTitle)
        .navigationSubtitle(projectVM.fileURL?.deletingLastPathComponent().path ?? "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { mode = .show } label: {
                    Label("Show Mode", systemImage: "play.rectangle.on.rectangle.fill")
                }
                .help("Enter Show Mode for live cue firing")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Script Selected")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Select a script from the list, or add a new one.")
                .font(.body)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
