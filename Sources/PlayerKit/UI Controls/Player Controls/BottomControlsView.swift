import SwiftUI

struct BottomControlsView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        VStack() {
            HStack {
                //PlaybackTimeView(playerManager: playerManager)
                AudioAndSubtitlesMenu(playerManager: playerManager)
                Spacer()
                PiPButton()
                RotateButtonView()
            }

            PlaybackSliderView(playerManager: playerManager)
        }
    }
}
