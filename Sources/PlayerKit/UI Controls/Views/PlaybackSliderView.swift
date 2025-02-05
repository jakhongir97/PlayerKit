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

            }
            .frame(height: 44)
        }
    }
}

