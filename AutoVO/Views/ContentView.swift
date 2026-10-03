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
        .navigationTitle(projectVM.displayName)
        .background {
            DocumentWindowBinder(url: projectVM.fileURL,
                                 isEdited: projectVM.isDirty,
                                 shouldClose: { projectVM.prepareForWindowClose() })
        }
        .background {
            // Invisible accelerator: ⇧⌘T toggles Edit ⇄ Show from anywhere. The
            // Show-mode key monitor ignores this keyCode, so it passes through.
            Button("Toggle Show Mode", action: toggleMode)
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .hidden()
        }
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
        .onChange(of: projectVM.project.scripts) { _, _ in
            cueList.setCues(projectVM.project.scripts)
        }
    }

    private func toggleMode() {
        withAnimation(.easeInOut(duration: 0.18)) {
            mode = (mode == .show) ? .edit : .show
        }
    }

    @ViewBuilder private var editPane: some View {
        if let id = projectVM.selectedScriptID,
           let idx = projectVM.project.scripts.firstIndex(where: { $0.id == id }) {
            ScriptEditorView(script: $projectVM.project.scripts[idx])
                // Re-create the editor per selected cue so its focus logic
                // (title vs. body) runs each time the selection changes.
                .id(id)
                .onChange(of: projectVM.project.scripts[idx]) { _, _ in
                    projectVM.isDirty = true
                }
                // Only the body feeds the render; renaming must not discard cached audio.
                .onChange(of: projectVM.project.scripts[idx].body) { _, _ in
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

/// Mirrors document state onto the hosting NSWindow, which SwiftUI doesn't expose:
/// the title-bar proxy icon (representedURL), the "Edited" indicator, and a close
/// guard (⌘W / close button) that can prompt to save.
private struct DocumentWindowBinder: NSViewRepresentable {
    let url: URL?
    let isEdited: Bool
    let shouldClose: () -> Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.shouldClose = shouldClose
        // The window isn't attached during the first update; apply on the next turn.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.representedURL = url
            window.isDocumentEdited = isEdited
            coordinator.installCloseGuard(on: window)
        }
    }

    final class Coordinator {
        var shouldClose: () -> Bool = { true }
        private var proxy: CloseGuardingWindowDelegate?

        /// Wrap SwiftUI's own window delegate (re-wrapping if SwiftUI swapped it).
        func installCloseGuard(on window: NSWindow) {
            if let proxy, window.delegate === proxy { return }
            let proxy = CloseGuardingWindowDelegate(wrapping: window.delegate) { [weak self] in
                self?.shouldClose() ?? true
            }
            self.proxy = proxy
            window.delegate = proxy
        }
    }
}

/// Answers `windowShouldClose` itself and forwards every other delegate message to the
/// delegate SwiftUI installed, so window behaviour is otherwise unchanged.
private final class CloseGuardingWindowDelegate: NSObject, NSWindowDelegate {
    private let wrapped: NSWindowDelegate?
    private let shouldClose: () -> Bool

    init(wrapping wrapped: NSWindowDelegate?, shouldClose: @escaping () -> Bool) {
        self.wrapped = wrapped
        self.shouldClose = shouldClose
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard shouldClose() else { return false }
        return wrapped?.windowShouldClose?(sender) ?? true
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (wrapped?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let wrapped, wrapped.responds(to: aSelector) { return wrapped }
        return super.forwardingTarget(for: aSelector)
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
