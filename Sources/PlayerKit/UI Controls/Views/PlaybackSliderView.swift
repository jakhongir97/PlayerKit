import SwiftUI

struct PlaybackSliderView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        VStack() {
            ZStack(alignment: .leading) {

                // Use MusicProgressSlider instead of default Slider
                MusicProgressSlider(
                    value: Binding(
                        get: { playerManager.isSeeking ? playerManager.seekTime : playerManager.currentTime },
                        set: { newValue in
                            playerManager.seekTime = newValue
                            if let player = playerManager.currentPlayer {
                                ThumbnailManager.shared.requestThumbnail(for: player, at: newValue)
                            }
                        }
                    ),
                    inRange: 0...max(playerManager.duration, 0.01),
                    activeFillColor: .white,
                    fillColor: .white.opacity(0.5),
                    emptyColor: .white.opacity(0.3),
                    height: 40
                ) { editing in
                    if editing {
                        playerManager.startSeeking()
                    } else {
                        playerManager.stopSeeking()
                    }
                }
                .frame(height: 40)
                .padding(.vertical)
                .contentShape(Rectangle()) // Ensures full slider area is tappable

                // Thumbnail preview while seeking
                if let thumbnail = ThumbnailManager.shared.thumbnailImage, playerManager.isSeeking {
                    GeometryReader { geometry in
                        let sliderWidth = geometry.size.width
                        let thumbPosition = sliderWidth * CGFloat(playerManager.seekTime / max(playerManager.duration, 0.01))

                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 67.5)
                            .cornerRadius(8)
                            .offset(x: min(max(thumbPosition - 60, 0), sliderWidth - 120), y: -80)
                    }
                }
            }
            .frame(height: 44)
        }
    }
}

