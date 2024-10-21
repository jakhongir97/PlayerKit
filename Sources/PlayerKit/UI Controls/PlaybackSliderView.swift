import SwiftUI

struct PlaybackSliderView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .leading) {
                Slider(
                    value: Binding(
                        get: { playerManager.isSeeking ? playerManager.seekTime : playerManager.currentTime },
                        set: { newValue in
                            playerManager.seekTime = newValue
                            if let player = playerManager.currentPlayer {
                                ThumbnailManager.shared.requestThumbnail(for: player, at: newValue)
                            }
                        }
                    ),
                    in: 0...max(playerManager.duration, 0.01),
                    onEditingChanged: { editing in
                        if editing {
                            playerManager.startSeeking()
                        } else {
                            playerManager.stopSeeking()
                        }
                    }
                )
                .accentColor(.blue)

                // Display the thumbnail preview while seeking
                if let thumbnail = ThumbnailManager.shared.thumbnailImage {
                    GeometryReader { geometry in
                        let sliderWidth = geometry.size.width
                        let thumbPosition = sliderWidth * CGFloat(playerManager.seekTime / max(playerManager.duration, 0.01))

                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 67.5)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                            .offset(x: min(max(thumbPosition - 60, 0), sliderWidth - 120), y: -80)
                    }
                }
            }
            .frame(height: 44)
        }
    }
}

