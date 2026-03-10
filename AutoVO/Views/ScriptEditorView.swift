import SwiftUI

struct ScriptEditorView: View {
    @Binding var script: Script

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(script.title.isEmpty ? "Untitled Script" : script.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Text(script.body.isEmpty ? "0 words" : "\(wordCount) words")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
        }
    }

    private var wordCount: Int {
        script.body
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
}
