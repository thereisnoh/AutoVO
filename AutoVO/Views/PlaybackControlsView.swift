import SwiftUI

struct PlaybackControlsView: View {
    @ObservedObject var playback: PlaybackViewModel
    @EnvironmentObject var projectVM: ProjectViewModel

    var body: some View {
        HStack(spacing: 16) {
            // Progress label
            if playback.state != .idle && playback.totalCount > 0 {
                Text("\(playback.currentIndex + 1) / \(playback.totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            // Stop
            Button {
                playback.stop()
            } label: {
                Image(systemName: "stop.fill")
            }
            .disabled(playback.state == .idle)
            .help("Stop")

            // Play / Pause
            if playback.state == .playing {
                Button {
                    playback.pause()
                } label: {
                    Image(systemName: "pause.fill")
                }
                .help("Pause")
            } else if playback.state == .paused {
                Button {
                    playback.resume()
                } label: {
                    Image(systemName: "play.fill")
                }
                .help("Resume")
            } else {
                Button {
                    playback.playAll(scripts: projectVM.project.scripts)
                } label: {
                    Image(systemName: "play.fill")
                }
                .disabled(projectVM.project.scripts.isEmpty)
                .help("Play All")
            }

            // Skip
            Button {
                playback.skip()
            } label: {
                Image(systemName: "forward.fill")
            }
            .disabled(playback.state != .playing)
            .help("Skip to Next")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
