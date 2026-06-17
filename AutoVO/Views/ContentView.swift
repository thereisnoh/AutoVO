import SwiftUI

/// QLab-style single-window shell: three stacked panes (Control / Cues / Edit).
/// "Edit" vs "Show" is an in-place state on the same shell — Show mode collapses
/// the edit pane and enables keyboard cue control, rather than swapping screens.
struct ContentView: View {
    @EnvironmentObject var projectVM: ProjectViewModel
    @EnvironmentObject var cueList: CueListViewModel
    @EnvironmentObject var render: CueRenderService

    enum Mode { case edit, show }
    @State private var mode: Mode = .edit
    @State private var editPaneHeight: CGFloat = 240

    var body: some View {
        VStack(spacing: 0) {
            ControlPaneView(mode: $mode)
            Divider()
            CueListPaneView(mode: mode)
                .frame(maxHeight: .infinity)
            if mode == .edit {
                PaneDivider(height: $editPaneHeight)
                editPane
                    .frame(height: editPaneHeight)
            }
        }
        .preferredColorScheme(.dark)
        .background(Color(white: 0.11))
        .overlay {
            if mode == .show {
                CueKeyboardCatcher(
                    onGo: { cueList.go() },
                    onStop: { cueList.panic() },
                    onArmNext: { cueList.armNext() },
                    onArmPrevious: { cueList.armPrevious() }
                )
                .frame(width: 0, height: 0)
            }
        }
        .onAppear { cueList.setCues(projectVM.project.scripts) }
        .onChange(of: projectVM.project.scripts) { _ in
            cueList.setCues(projectVM.project.scripts)
        }
    }

    @ViewBuilder private var editPane: some View {
        if let id = projectVM.selectedScriptID,
           let idx = projectVM.project.scripts.firstIndex(where: { $0.id == id }) {
            ScriptEditorView(script: $projectVM.project.scripts[idx])
                .onChange(of: projectVM.project.scripts[idx]) { _ in
                    projectVM.isDirty = true
                    render.invalidate(scriptID: id)
                }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text("Select a cue to edit")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Draggable horizontal splitter that resizes the pane below it.
struct PaneDivider: View {
    @Binding var height: CGFloat
    @State private var startHeight: CGFloat?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.35)).frame(height: 9)
            Capsule().fill(Color.white.opacity(0.18)).frame(width: 40, height: 4)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    let base = startHeight ?? height
                    if startHeight == nil { startHeight = height }
                    height = max(140, min(560, base - value.translation.height))
                }
                .onEnded { _ in startHeight = nil }
        )
        .onHover { inside in
            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
    }
}
