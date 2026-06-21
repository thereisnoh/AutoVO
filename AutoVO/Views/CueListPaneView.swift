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
                        // Single-click selection stays native/instant (List handles it).
                        // Double-click arms, detected at the AppKit level so it doesn't
                        // impose SwiftUI's wait-for-second-click delay on single clicks.
                        .background(DoubleClickCatcher { cueList.arm(script.id) })
                        .listRowSeparator(.hidden)
                        .listRowBackground(
                            index(of: script).isMultiple(of: 2)
                                ? Color.white.opacity(0.04) : Color.clear
                        )
                        .contextMenu {
                            Button("Arm Cue") { cueList.arm(script.id) }
                            Button("Play (Preview)") { cueList.preview(script) }
                            Button("Duplicate") { projectVM.duplicateScript(id: script.id) }
                            Divider()
                            Button("Delete", role: .destructive) { projectVM.deleteScript(id: script.id) }
                                .disabled(mode == .show)
                        }
                    }
                    .onMove { from, to in projectVM.moveScripts(from: from, to: to) }
                    // Swipe-to-delete is disabled in Show mode (passing nil removes it).
                    .onDelete(perform: deleteHandler)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onChange(of: cueList.armedCueID) { _, armed in
                    if mode == .show, let armed { withAnimation { proxy.scrollTo(armed, anchor: .center) } }
                }
            }
        }
    }

    /// Swipe-to-delete handler, or nil in Show mode to disable the gesture.
    private var deleteHandler: ((IndexSet) -> Void)? {
        mode == .show ? nil : { offsets in projectVM.deleteScripts(at: offsets) }
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
            .disabled(mode == .show)
            .help("Add cue")
            Button {
                if let id = projectVM.selectedScriptID { projectVM.deleteScript(id: id) }
            } label: {
                Image(systemName: "trash")
            }
            .disabled(projectVM.selectedScriptID == nil || mode == .show)
            .help("Delete selected cue")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

/// Transparent observer that fires `onDoubleClick` when a double-click lands inside
/// its frame. It watches the event stream without consuming events, so the List's
/// native single-click selection, drag-reorder, and context menu are untouched (and
/// single-click selection stays instant — no wait-for-double delay).
struct DoubleClickCatcher: NSViewRepresentable {
    var onDoubleClick: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }

    final class CatcherView: NSView {
        var onDoubleClick: () -> Void = {}
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window == nil ? removeMonitor() : installMonitor()
        }

        private func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, let window = self.window,
                      event.window == window, event.clickCount == 2 else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(point) { self.onDoubleClick() }
                return event   // never consume — selection/drag/menu stay native
            }
        }

        private func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { removeMonitor() }
    }
}
