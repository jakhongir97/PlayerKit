import SwiftUI

struct ControlMenuView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        HStack(spacing: 16) {
            // Subtitle Menu
            subtitleMenu()

            // Audio Menu
            audioMenu()

            // Video Menu
            videoMenu()

            // Playback Speed Menu
            playbackSpeedMenu()

            Spacer()  // Keeps buttons aligned to the left
        }
    }

    @ViewBuilder
    func subtitleMenu() -> some View {
        Menu {
            ForEach(playerManager.availableSubtitles.indices, id: \.self) { index in
                Button(action: {
                    playerManager.selectSubtitle(index: index)
                }) {
                    Text(playerManager.availableSubtitles[index])
                }
            }
        } label: {
            Label("Subtitles", systemImage: "captions.bubble")
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
        }
    }

    @ViewBuilder
    func audioMenu() -> some View {
        Menu {
            ForEach(playerManager.availableAudioTracks.indices, id: \.self) { index in
                Button(action: {
                    playerManager.selectAudioTrack(index: index)
                }) {
                    Text(playerManager.availableAudioTracks[index])
                }
            }
        } label: {
            Label("Audio", systemImage: "speaker.wave.2")
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
        }
    }

    @ViewBuilder
    func videoMenu() -> some View {
        Menu {
            ForEach(playerManager.availableVideoTracks.indices, id: \.self) { index in
                Button(action: {
                    playerManager.selectVideoTrack(index: index)
                }) {
                    Text(playerManager.availableVideoTracks[index])
                }
            }
        } label: {
            Label("Video", systemImage: "film")
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
        }
    }

    @ViewBuilder
    func playbackSpeedMenu() -> some View {
        Menu {
            Button("0.25x") { playerManager.playbackSpeed = 0.25 }
            Button("0.5x") { playerManager.playbackSpeed = 0.5 }
            Button("1.0x (Normal)") { playerManager.playbackSpeed = 1.0 }
            Button("1.25x") { playerManager.playbackSpeed = 1.25 }
            Button("1.5x") { playerManager.playbackSpeed = 1.5 }
        } label: {
            Label("Speed", systemImage: "tortoise")
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
        }
    }
}

