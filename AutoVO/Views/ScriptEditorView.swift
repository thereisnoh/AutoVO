import SwiftUI
import AppKit

struct ScriptEditorView: View {
    @Binding var script: Script
    @EnvironmentObject var cueList: CueListViewModel

    @FocusState private var focus: Field?

    private enum Field { case title, body }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                // An empty title is "automatic": the placeholder shows the name derived
                // from the body, so it reads as grey ghost text and follows typing live.
                TextField(script.displayTitle, text: $script.title)
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

            TextEditor(text: $script.body)
                .font(.body)
                .padding(8)
                .focused($focus, equals: .body)
        }
        // Drop the cursor at the end of the script body (new cues included: the name
        // fills itself in from the body, so there's nothing to type in the title first).
        .onAppear { focusBody() }
    }

    /// Move focus to the body editor with the caret at the end of the text.
    /// (SwiftUI's `TextEditor` caret-placement API is macOS 15+, so we drive the
    /// underlying field editor via an AppKit text action once it's first responder.)
    private func focusBody() {
        focus = .body
        sendTextActionSoon("moveToEndOfDocument:")
    }

    /// Dispatch an AppKit text-editing action to the first responder after focus settles.
    private func sendTextActionSoon(_ action: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.sendAction(Selector(action), to: nil, from: nil)
        }
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
