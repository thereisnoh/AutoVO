import SwiftUI

/// Middle pane: the main cue list. Clicking a cue selects it (for the edit pane);
/// arming the standby is separate (context menu, or ↑/↓ in Show mode). Supports
/// drag-reorder and delete.
struct CueListPaneView: View {
    @EnvironmentObject var projectVM: ProjectViewModel
    @EnvironmentObject var cueList: CueListViewModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var render: CueRenderService
    let mode: ContentView.Mode

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                List(selection: $projectVM.selectedScriptID) {
                    ForEach(projectVM.project.scripts) { script in
                        CueRowView(
                            index: index(of: script),
                            script: script,
                            isArmed: cueList.armedCueID == script.id,
                            isPlaying: cueList.playingCueID == script.id,
                            isFired: cueList.firedCueIDs.contains(script.id),
                            isSelected: projectVM.selectedScriptID == script.id,
                            status: render.currentStatus(for: script, settings: settings)
                        )
                        .tag(script.id)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            Button("Arm Cue") { cueList.arm(script.id) }
                            Button("Play (Preview)") { cueList.preview(script) }
                            Button("Duplicate") { projectVM.duplicateScript(id: script.id) }
                            Divider()
                            Button("Delete", role: .destructive) { projectVM.deleteScript(id: script.id) }
                        }
                    }
                    .onMove { from, to in projectVM.moveScripts(from: from, to: to) }
                    .onDelete { offsets in projectVM.deleteScripts(at: offsets) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onChange(of: cueList.armedCueID) { _, armed in
                    if mode == .show, let armed { withAnimation { proxy.scrollTo(armed, anchor: .center) } }
                }
            }
        }
    }

    private func index(of script: Script) -> Int {
        projectVM.project.scripts.firstIndex { $0.id == script.id } ?? 0
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("CUES")
                .font(.caption).fontWeight(.bold).tracking(1.5)
                .foregroundStyle(.secondary)
            Text("\(projectVM.project.scripts.count)")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
            Button { cueList.resetShow() } label: {
                Image(systemName: "backward.end.fill")
            }
            .help("Arm first cue / clear fired markers")
            Button { projectVM.addScript() } label: {
                Image(systemName: "plus")
            }
            .help("Add cue")
            Button {
                if let id = projectVM.selectedScriptID { projectVM.deleteScript(id: id) }
            } label: {
                Image(systemName: "trash")
            }
            .disabled(projectVM.selectedScriptID == nil)
            .help("Delete selected cue")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
