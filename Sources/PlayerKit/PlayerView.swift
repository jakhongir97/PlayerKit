import SwiftUI

public struct PlayerView: View {
    @ObservedObject var playerManager = PlayerManager.shared

    public init() {}  // Public initializer to allow creation of PlayerView

    public var body: some View {
        ZStack {
            // Video rendering view for both AVPlayer and VLCPlayer
            PlayerRenderingView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

            VStack {
                Spacer()

                // Play/Pause Button and Progress Bar
                HStack {
                    Button(action: {
                        playerManager.isPlaying ? playerManager.pause() : playerManager.play()
                    }) {
                        Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 30))
                            .padding()
                            .background(Color.white.opacity(0.7))
                            .cornerRadius(50)
                    }

                    Spacer()

                    // Current Time / Duration and Seek Bar
                    Text(TimeFormatter.shared.formatTime(playerManager.currentTime))
                    Slider(value: Binding(
                        get: { playerManager.currentTime },
                        set: { newValue in playerManager.seek(to: newValue) }
                    ), in: 0...playerManager.duration)
                    Text(TimeFormatter.shared.formatTime(playerManager.duration))
                }
                .padding()

                // Audio Track and Subtitle Selection (if needed)
                HStack {
                    if !playerManager.availableSubtitles.isEmpty {
                        Menu {
                            ForEach(playerManager.availableSubtitles.indices, id: \.self) { index in
                                Button(action: {
                                    playerManager.selectSubtitle(index: index)
                                }) {
                                    Text(playerManager.availableSubtitles[index])
                                }
                            }
                        } label: {
                            Text("Subtitles")
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                        }
                    }

                    if !playerManager.availableAudioTracks.isEmpty {
                        Menu {
                            ForEach(playerManager.availableAudioTracks.indices, id: \.self) { index in
                                Button(action: {
                                    playerManager.selectAudioTrack(index: index)
                                }) {
                                    Text(playerManager.availableAudioTracks[index])
                                }
                            }
                        } label: {
                            Text("Audio Tracks")
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.bottom)
            }
        }
    }
}

