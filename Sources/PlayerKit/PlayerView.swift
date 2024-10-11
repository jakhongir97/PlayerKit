import SwiftUI
import AVFoundation

public struct PlayerView: View {
    @ObservedObject var playerManager = PlayerManager.shared

    public init() {}

    public var body: some View {
        ZStack {
            // Video rendering view for both AVPlayer and VLCPlayer
            renderPlayerView()
                .edgesIgnoringSafeArea(.all)

            VStack {
                Spacer()

                // Play/Pause button centered vertically and horizontally
                playPauseButton()
                    .padding(.bottom, 16)

                Spacer()

                // Slider, current time, and duration in one line
                playbackSlider()
                    .padding([.leading, .trailing], 16)

                // Audio and Subtitle buttons below the slider aligned to the left
                audioSubtitleMenu()
                    .padding([.leading], 16)
                    .padding(.bottom, 16)
            }
        }
    }
}

// MARK: - Player Rendering View
extension PlayerView {
    @ViewBuilder
    func renderPlayerView() -> some View {
        PlayerRenderingView()  // Video rendering view for both AVPlayer and VLCPlayer
            .background(Color.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Play/Pause Button
extension PlayerView {
    @ViewBuilder
    func playPauseButton() -> some View {
        HStack {
            Spacer()  // Push button to the center horizontally

            Button(action: {
                playerManager.isPlaying ? playerManager.pause() : playerManager.play()
            }) {
                Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .resizable()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.white)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }

            Spacer()  // Push button to the center horizontally
        }
        .frame(maxHeight: .infinity)  // Ensures it's vertically centered
    }
}

// MARK: - Playback Slider with Time Indicator (Center Dot) and Buffering Indicator
extension PlayerView {
    @ViewBuilder
    func playbackSlider() -> some View {
        HStack {
            Slider(
                value: Binding(
                    get: { playerManager.isSeeking ? playerManager.seekTime : playerManager.currentTime },
                    set: { newValue in
                        playerManager.seekTime = newValue
                        playerManager.startSeeking()  // Start seeking when user interacts
                    }
                ),
                in: 0...playerManager.duration,
                onEditingChanged: { editing in
                    if !editing {
                        playerManager.stopSeeking()  // Stop seeking once user finishes dragging
                    }
                }
            )
            .accentColor(.blue)

            Text(TimeFormatter.shared.formatTime(playerManager.currentTime))
                .foregroundColor(.white)
            Text("•")
                .foregroundColor(.white)
            Text(TimeFormatter.shared.formatTime(playerManager.duration))
                .foregroundColor(.white)

            if playerManager.isBuffering {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
            }
        }
    }
}

// MARK: - Audio and Subtitle Menus Below the Slider
extension PlayerView {
    @ViewBuilder
    func audioSubtitleMenu() -> some View {
        HStack(spacing: 16) {  // Aligning buttons side by side with some spacing
            // Subtitle Menu
            subtitleMenu()

            // Audio Menu
            audioMenu()

            Spacer()  // Ensures the buttons stay aligned to the left edge
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
}

