import SwiftUI

/// One row in the cue list. Styling reflects armed / playing / fired / selected
/// state plus the cue's render status. Selection is handled by the enclosing
/// List; arming is a separate action (context menu or ↑/↓ in Show mode).
struct CueRowView: View {
    let index: Int
    let script: Script
    let isArmed: Bool
    let isPlaying: Bool
    let isFired: Bool
    var isSelected: Bool = false
    let status: CueRenderStatus
    var onArm: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(isArmed ? Color.accentColor : .secondary)
                .frame(width: 28, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(script.title.isEmpty ? "Untitled Cue" : script.title)
                    .fontWeight(isArmed ? .semibold : .regular)
                    .foregroundStyle(isFired && !isArmed && !isPlaying ? .secondary : .primary)
                    .lineLimit(1)
                if !script.body.isEmpty {
                    Text(script.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isArmed {
                Text("ARMED")
                    .font(.caption2).fontWeight(.bold).tracking(1)
                    .foregroundStyle(Color.accentColor)
            }
            statusView
            // Reserve the indicator's footprint at all times so arming/playing a
            // cue doesn't shift the row layout (the bars only appear while playing).
            ZStack {
                if isPlaying { WaveformIndicator() }
            }
            .frame(width: 18, height: 16)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isPlaying ? Color.accentColor.opacity(0.22)
                      : (isArmed ? Color.accentColor.opacity(0.10) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isArmed ? Color.accentColor.opacity(0.8) : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder private var statusView: some View {
        switch status {
        case .needsRender:
            Image(systemName: "circle").foregroundStyle(.tertiary).help("Not rendered")
        case .rendering:
            ProgressView().controlSize(.small)
        case .ready:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Ready")
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).help(message)
        }
    }
}

/// Animated "playing" indicator (4 bars).
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
