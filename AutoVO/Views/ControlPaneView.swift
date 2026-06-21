import SwiftUI

/// Top pane: transport + the armed/standby cue. Always present; in Show mode the
/// GO/transport is emphasized. Drives the whole show via CueListViewModel.
struct ControlPaneView: View {
    @EnvironmentObject var cueList: CueListViewModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var deviceService: AudioDeviceService
    @Binding var mode: ContentView.Mode

    private var isShow: Bool { mode == .show }

    var body: some View {
        VStack(spacing: 8) {
            if deviceMissing { deviceBanner }
            HStack(alignment: .center, spacing: 16) {
                modeToggle
                Divider().frame(height: 38)
                armedInfo
                Spacer(minLength: 12)
                Toggle("Auto next cue", isOn: $cueList.autoNextCue)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                    .help("Advance the standby to the next cue after this cue finishes")
                transport
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isShow ? 16 : 10)
        .background(isShow ? Color.black.opacity(0.45) : Color.white.opacity(0.03))
        .animation(.easeInOut(duration: 0.18), value: isShow)
    }

    private var modeToggle: some View {
        Picker("", selection: $mode) {
            Text("Edit").tag(ContentView.Mode.edit)
            Text("Show").tag(ContentView.Mode.show)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 132)
    }

    private var armedInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(cueList.state == .playing ? "ON AIR" : "STANDBY")
                    .font(.caption2).fontWeight(.bold).tracking(1.5)
                    .foregroundStyle(cueList.state == .playing ? .green : .orange)
                if cueList.state == .playing || cueList.state == .paused {
                    Text("\(fmt(cueList.elapsed)) / -\(fmt(cueList.remaining))")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Text(armedTitle)
                .font(isShow ? .title2 : .headline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .foregroundStyle(cueList.armedCue == nil ? .secondary : .primary)
        }
        .frame(minWidth: 160, alignment: .leading)
    }

    private var armedTitle: String {
        guard let cue = cueList.armedCue else { return "No cue armed" }
        let n = (cueList.armedIndex ?? 0) + 1
        return "\(n).  \(cue.title.isEmpty ? "Untitled Cue" : cue.title)"
    }

    private var transport: some View {
        HStack(spacing: 12) {
            Button { cueList.panic() } label: {
                Image(systemName: "stop.fill")
            }
            .tint(.red)
            .disabled(cueList.state == .standby || cueList.state == .stopped)
            .help("Stop / panic")

            Button {
                cueList.state == .paused ? cueList.resume() : cueList.pause()
            } label: {
                Image(systemName: cueList.state == .paused ? "play.fill" : "pause.fill")
            }
            .disabled(cueList.state != .playing && cueList.state != .paused)
            .help("Pause / resume")

            Button { cueList.go() } label: {
                Text(cueList.state == .firing ? "…" : "GO")
                    .font(.system(size: isShow ? 24 : 16, weight: .heavy))
                    .frame(minWidth: isShow ? 104 : 60, minHeight: isShow ? 44 : 26)
            }
            .tint(.green)
            .disabled(goDisabled)
            .help("Fire the armed cue (Space in Show mode)")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(isShow ? .large : .regular)
    }

    private var goDisabled: Bool {
        cueList.armedCueID == nil
            || cueList.state == .firing
            || cueList.state == .playing
            || cueList.state == .paused
    }

    private var deviceMissing: Bool {
        guard let id = settings.selectedAudioDeviceID else { return false }
        return !deviceService.outputDevices.contains { $0.id == id }
    }

    private var deviceBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Selected output device unavailable — using system default")
                .font(.callout)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.orange.opacity(0.20))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func fmt(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
