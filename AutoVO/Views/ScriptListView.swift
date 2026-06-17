import SwiftUI

struct ScriptListView: View {
    @EnvironmentObject var projectVM: ProjectViewModel
    @ObservedObject var playback: PlaybackViewModel

    var body: some View {
        List(selection: $projectVM.selectedScriptID) {
            ForEach($projectVM.project.scripts) { $script in
                ScriptRowView(
                    script: script,
                    isPlaying: playback.currentScriptID == script.id && playback.state == .playing
                )
                .tag(script.id)
                .contextMenu {
                    Button("Duplicate") {
                        projectVM.duplicateScript(id: script.id)
                    }
                    Button("Play This Script") {
                        playback.playOne(script: script)
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        projectVM.deleteScript(id: script.id)
                    }
                }
            }
            .onMove { indices, newOffset in
                projectVM.moveScripts(from: indices, to: newOffset)
            }
            .onDelete { offsets in
                projectVM.deleteScripts(at: offsets)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    projectVM.addScript()
                } label: {
                    Label("Add Script", systemImage: "plus")
                }
                .help("Add Script")

                Button {
                    if let id = projectVM.selectedScriptID {
                        projectVM.deleteScript(id: id)
                    }
                } label: {
                    Label("Delete Script", systemImage: "trash")
                }
                .disabled(projectVM.selectedScriptID == nil)
                .help("Delete Script")

                Divider()

                Button {
                    if let id = projectVM.selectedScriptID,
                       let script = projectVM.project.scripts.first(where: { $0.id == id }) {
                        playback.playOne(script: script)
                    } else {
                        playback.playAll(scripts: projectVM.project.scripts)
                    }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .disabled(projectVM.project.scripts.isEmpty)
                .help("Play")
            }
        }
    }
}
