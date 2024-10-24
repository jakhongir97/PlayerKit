import SwiftUI

struct PlayerControlsView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        ZStack {
            // Play/Pause button in the center
            VStack {
                Spacer()
                PlayPauseButtonView(playerManager: playerManager)
                    .frame(maxWidth: .infinity)
                Spacer()
            }

            // Playback slider and menu at the bottom
            VStack(spacing: 0) {
                Spacer()
                ControlMenuView(playerManager: playerManager)
                    .padding([.leading, .trailing], 16)
                PlaybackSliderView(playerManager: playerManager)
                    .padding([.leading, .trailing], 16)
                    .padding(.bottom, 16)                
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
