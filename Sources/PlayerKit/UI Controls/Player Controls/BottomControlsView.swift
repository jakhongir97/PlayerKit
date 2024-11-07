import SwiftUI

struct BottomControlsView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        VStack() {
            HStack {
                //PlaybackTimeView(playerManager: playerManager)
                Spacer()
                AudioAndSubtitlesMenu(playerManager: playerManager)
            }

            PlaybackSliderView(playerManager: playerManager)
        }
    }
}
