import SwiftUI

struct ScriptRowView: View {
    let script: Script
    let isPlaying: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(script.title.isEmpty ? "Untitled Script" : script.title)
                    .lineLimit(1)
                if !script.body.isEmpty {
                    Text(script.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isPlaying {
                WaveformIndicator()
            }
        }
        .padding(.vertical, 2)
    }
}

struct WaveformIndicator: View {
    @State private var phase: Double = 0

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .frame(width: 3, height: barHeight(for: i))
                    .foregroundColor(.accentColor)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.12),
                        value: phase
                    )
            }
        }
        .frame(width: 18, height: 16)
        .onAppear { phase = 1 }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let heights: [CGFloat] = [8, 14, 10, 6]
        let animated: [CGFloat] = [14, 6, 14, 12]
        return phase == 0 ? heights[index] : animated[index]
    }
}
