import SwiftUI

/// High-contrast operator surface for live cue firing. Driven entirely by
/// `CueListViewModel`; keyboard-controllable (Space=GO, Esc=STOP, ↑/↓ arm).
struct ShowModeView: View {
    @EnvironmentObject var cueList: CueListViewModel
    @EnvironmentObject var projectVM: ProjectViewModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var render: CueRenderService
    @Binding var mode: ContentView.Mode

    var body: some View {
        VStack(spacing: 0) {
            header
            tintedDivider
            armedPanel.padding(20)
            tintedDivider
            cueListView
            transportBar
        }
        .background(Color(white: 0.07))
        .foregroundStyle(.white)
        .overlay(
            CueKeyboardCatcher(
                onGo: { cueList.go() },
                onStop: { cueList.panic() },
                onArmNext: { cueList.armNext() },
                onArmPrevious: { cueList.armPrevious() }
            )
            .frame(width: 0, height: 0)
        )
        .onAppear { cueList.setCues(projectVM.project.scripts) }
    }

    private var tintedDivider: some View {
        Divider().overlay(Color.white.opacity(0.12))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button { mode = .edit } label: {
                Label("Edit", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .help("Return to Edit Mode")

            Spacer()
            Text("SHOW · \(showName)")
                .font(.headline)
                .tracking(1)
            Spacer()

            Toggle(isOn: $cueList.stopAfterArmed) {
                Text("Stop after cue")
            }
            .toggleStyle(.switch)
            .help("Hold instead of advancing the standby after the cue finishes")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var showName: String {
        projectVM.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    // MARK: - Armed panel

    private var armedPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(cueList.state == .playing ? "ON AIR" : "STANDBY")
                    .font(.caption)
                    .fontWeight(.bold)
                    .tracking(2)
                    .foregroundStyle(cueList.state == .playing ? .green : .orange)
                Spacer()
                timeView
            }

            if let cue = cueList.armedCue {
                Text(cue.title.isEmpty ? "Untitled Cue" : cue.title)
                    .font(.system(size: 30, weight: .bold))
                    .lineLimit(2)
                Text(cue.body.isEmpty ? "(empty)" : cue.body)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            } else {
                Text("No cues — add scripts in Edit Mode")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
    }

    @ViewBuilder private var timeView: some View {
        Group {
            if cueList.state == .playing || cueList.state == .paused {
                HStack(spacing: 8) {
                    Text(fmt(cueList.elapsed))
                    Text("/").foregroundStyle(.secondary)
                    Text("-\(fmt(cueList.remaining))").foregroundStyle(.orange)
                }
            } else if let cue = cueList.armedCue,
                      let rendered = render.rendered(for: cue, settings: settings) {
                Text(fmt(rendered.duration)).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 26, weight: .semibold, design: .monospaced))
    }

    // MARK: - Cue list

    private var cueListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(cueList.cues.enumerated()), id: \.element.id) { idx, cue in
                        CueRowView(
                            index: idx,
                            script: cue,
                            isArmed: cueList.armedCueID == cue.id,
                            isPlaying: cueList.playingCueID == cue.id,
                            isFired: cueList.firedCueIDs.contains(cue.id),
                            status: render.currentStatus(for: cue, settings: settings),
                            onArm: { cueList.arm(cue.id) }
                        )
                        .id(cue.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: cueList.armedCueID) { armed in
                if let armed { withAnimation { proxy.scrollTo(armed, anchor: .center) } }
            }
        }
    }

    // MARK: - Transport

    private var transportBar: some View {
        HStack(spacing: 16) {
            Button { cueList.panic() } label: {
                Label("STOP", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .tint(.red)
            .disabled(cueList.state == .standby || cueList.state == .stopped)

            Button { cueList.go() } label: {
                Text(cueList.state == .firing ? "…" : "GO")
                    .font(.system(size: 28, weight: .heavy))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .tint(.green)
            .disabled(cueList.armedCueID == nil
                      || cueList.state == .firing
                      || cueList.state == .playing
                      || cueList.state == .paused)

            Button {
                cueList.state == .paused ? cueList.resume() : cueList.pause()
            } label: {
                Image(systemName: cueList.state == .paused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .disabled(cueList.state != .playing && cueList.state != .paused)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(16)
    }

    private func fmt(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
