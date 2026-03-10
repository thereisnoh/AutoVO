import SwiftUI

struct ContentView: View {
    @EnvironmentObject var projectVM: ProjectViewModel
    @EnvironmentObject var playback: PlaybackViewModel

    var body: some View {
        NavigationSplitView {
            ScriptListView(playback: playback)
                .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        } detail: {
            if let selectedID = projectVM.selectedScriptID,
               let idx = projectVM.project.scripts.firstIndex(where: { $0.id == selectedID }) {
                ScriptEditorView(script: $projectVM.project.scripts[idx])
                    .onChange(of: projectVM.project.scripts[idx]) { _ in
                        projectVM.isDirty = true
                    }
            } else {
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
        .safeAreaInset(edge: .bottom) {
            PlaybackControlsView(playback: playback)
        }
        .navigationTitle(projectVM.windowTitle)
        .navigationSubtitle(projectVM.fileURL?.deletingLastPathComponent().path ?? "")
    }
}
