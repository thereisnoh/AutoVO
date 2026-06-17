import SwiftUI

/// One row in the Show Mode cue list. Styling reflects armed / playing / fired
/// state plus the cue's render status. Tapping arms the cue.
struct CueRowView: View {
    let index: Int
    let script: Script
    let isArmed: Bool
    let isPlaying: Bool
    let isFired: Bool
    let status: CueRenderStatus
    let onArm: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(isArmed ? Color.accentColor : .secondary)
                .frame(width: 30, alignment: .trailing)

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

            statusView
            if isPlaying { WaveformIndicator() }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isArmed ? Color.accentColor : .clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onArm)
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

    private var background: Color {
        if isPlaying { return Color.accentColor.opacity(0.30) }
        if isArmed { return Color.accentColor.opacity(0.12) }
        return Color.white.opacity(0.04)
    }
}
