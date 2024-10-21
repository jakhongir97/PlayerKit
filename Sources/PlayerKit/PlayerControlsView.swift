import SwiftUI

struct PlayerControlsView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        VStack {
            Spacer()

            PlayPauseButtonView(playerManager: playerManager)
                .padding(.bottom, 16)

            Spacer()

            PlaybackSliderView(playerManager: playerManager)
                .padding([.leading, .trailing], 16)

            ControlMenuView(playerManager: playerManager)
                .padding([.leading], 16)
                .padding(.bottom, 16)
        }
    }
}
