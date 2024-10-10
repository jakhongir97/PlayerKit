import SwiftUI

public struct PlayerView: View {
    @ObservedObject var playerManager = PlayerManager.shared

    public init() {}

    public var body: some View {
        ZStack {
            // Rendering the Player (both AVPlayer and VLCPlayer)
            renderPlayerView()

            // Controls Layer: Play/Pause, Slider, Audio/Subtitle Tracks
            VStack {
                Spacer()

                // Play/Pause button in the center of the video
                playPauseButton()
                    .padding(.bottom, 16)

                Spacer()

                // Slider at the bottom with Time Indicators and Audio/Subtitle Menus
                VStack {
                    playbackSlider()
                    audioSubtitleMenu()
                }
                .padding([.leading, .trailing], 16)
                .padding(.bottom)
            }
        }
    }
}

extension PlayerView {

    // MARK: - Player Rendering View
    /// Renders the Player's Video view based on AVPlayer or VLCPlayer
    @ViewBuilder
    func renderPlayerView() -> some View {
        PlayerRenderingView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
    }

    // MARK: - Play/Pause Button
    /// Displays a centered Play/Pause button
    @ViewBuilder
    func playPauseButton() -> some View {
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
    }

    // MARK: - Playback Slider with Time Indicators
    /// Handles the playback slider and time updates
    @ViewBuilder
    func playbackSlider() -> some View {
        HStack {
            Text(TimeFormatter.shared.formatTime(playerManager.isSeeking ? playerManager.seekTime : playerManager.currentTime))
            Slider(
                value: Binding(
                    get: { playerManager.isSeeking ? playerManager.seekTime : playerManager.currentTime },
                    set: { newValue in
                        playerManager.seekTime = newValue  // Update the seek time while dragging
                        playerManager.startSeeking()  // Track that the user is interacting
                    }
                ),
                in: 0...playerManager.duration,
                onEditingChanged: { editing in
                    if !editing {  // User finished dragging
                        playerManager.stopSeeking()  // Seek to the selected time and reset state
                    }
                }
            )
            Text(TimeFormatter.shared.formatTime(playerManager.duration))
        }
    }

    // MARK: - Audio and Subtitle Menus
    /// Shows menus for selecting Audio and Subtitle tracks (if available)
    @ViewBuilder
    func audioSubtitleMenu() -> some View {
        HStack {
            if !playerManager.availableSubtitles.isEmpty {
                subtitleMenu()
            }

            if !playerManager.availableAudioTracks.isEmpty {
                audioMenu()
            }
        }
    }

    // MARK: - Subtitle Menu
    /// Handles the subtitle track selection
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
            Text("Subtitles")
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
        }
    }

    // MARK: - Audio Menu
    /// Handles the audio track selection
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
            Text("Audio Tracks")
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
        }
    }
}

