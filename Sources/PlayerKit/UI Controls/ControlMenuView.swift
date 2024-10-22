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
            
            PiPButton()
            
            AirPlayRoutePickerView()
                .frame(width: 40, height: 40)
            
            PlaybackTimeView(playerManager: playerManager)

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
                    HStack {
                        Text(playerManager.availableSubtitles[index])
                        if playerManager.selectedSubtitleTrackIndex == index {
                            Image(systemName: "checkmark")
                        }
                    }
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
                    HStack {
                        Text(playerManager.availableAudioTracks[index])
                        if playerManager.selectedAudioTrackIndex == index {
                            Image(systemName: "checkmark")
                        }
                    }
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
                    HStack {
                        Text(playerManager.availableVideoTracks[index])
                        if playerManager.selectedVideoTrackIndex == index {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("Video", systemImage: "play.square.stack")
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
        }
    }

    @ViewBuilder
    func playbackSpeedMenu() -> some View {
        Menu {
            Button(action: {
                playerManager.playbackSpeed = 0.25
            }) {
                HStack {
                    Text("0.25x")
                    if playerManager.playbackSpeed == 0.25 {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Button(action: {
                playerManager.playbackSpeed = 0.5
            }) {
                HStack {
                    Text("0.5x")
                    if playerManager.playbackSpeed == 0.5 {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Button(action: {
                playerManager.playbackSpeed = 1.0
            }) {
                HStack {
                    Text("1.0x (Normal)")
                    if playerManager.playbackSpeed == 1.0 {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Button(action: {
                playerManager.playbackSpeed = 1.25
            }) {
                HStack {
                    Text("1.25x")
                    if playerManager.playbackSpeed == 1.25 {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Button(action: {
                playerManager.playbackSpeed = 1.5
            }) {
                HStack {
                    Text("1.5x")
                    if playerManager.playbackSpeed == 1.5 {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Label("Speed", systemImage: "play.circle")
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
        }
    }
}

