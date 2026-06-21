import SwiftUI
import AppKit

struct ScriptEditorView: View {
    @Binding var script: Script
    @EnvironmentObject var cueList: CueListViewModel
    @EnvironmentObject var projectVM: ProjectViewModel

    @FocusState private var focus: Field?

    private enum Field { case title, body }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField("Script title", text: titleBinding)
                    .font(.headline)
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .title)
                    // Tab from the title moves the cursor into the script body.
                    .onKeyPress(.tab) {
                        focusBody()
                        return .handled
                    }

                Spacer()

                Text(statsLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Button {
                    cueList.preview(script)
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .help("Preview this cue")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            TextEditor(text: Binding(
                get: { script.body },
                set: { newValue in
                    script.body = newValue
                    script.updateTitle()
                }
            ))
            .font(.body)
            .padding(8)
            .focused($focus, equals: .body)
        }
        .onAppear {
            if projectVM.newlyAddedScriptID == script.id {
                // Freshly created cue: focus the title and select it so typing replaces it.
                projectVM.newlyAddedScriptID = nil
                focus = .title
                selectAllInFieldEditor()
            } else {
                // Existing cue: drop the cursor at the end of the script body.
                focusBody()
            }
        }
    }

    /// Move focus to the body editor with the caret at the end of the text.
    /// (SwiftUI's `TextEditor` caret-placement API is macOS 15+, so we drive the
    /// underlying field editor via an AppKit text action once it's first responder.)
    private func focusBody() {
        focus = .body
        sendTextActionSoon("moveToEndOfDocument:")
    }

    /// Select-all in the currently focused field editor (no SwiftUI API for this on
    /// a TextField), used so a new cue's title can be typed over immediately.
    private func selectAllInFieldEditor() {
        sendTextActionSoon("selectAll:")
    }

    /// Dispatch an AppKit text-editing action to the first responder after focus settles.
    private func sendTextActionSoon(_ action: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.sendAction(Selector(action), to: nil, from: nil)
        }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { script.title },
            set: { newValue in
                script.title = newValue
                script.hasCustomTitle = true
            }
        )
    }

    private var statsLabel: String {
        let words = script.body
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
        let chars = script.body.count
        return "\(words)w · \(chars)c"
    }
}
