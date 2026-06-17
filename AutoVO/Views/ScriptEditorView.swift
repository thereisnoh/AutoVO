import SwiftUI

struct ScriptEditorView: View {
    @Binding var script: Script
    @EnvironmentObject var cueList: CueListViewModel

    @FocusState private var focus: Field?

    private enum Field { case title, body }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField("Script title", text: titleBinding)
                    .font(.headline)
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .title)

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
            if script.body.isEmpty {
                focus = .body
            }
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
