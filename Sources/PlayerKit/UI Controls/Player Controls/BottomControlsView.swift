import SwiftUI

struct BottomControlsView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                //PlaybackTimeView(playerManager: playerManager)
                Spacer()
                AudioAndSubtitlesMenu(playerManager: playerManager)
            }
            .padding([.leading, .trailing], 16)

            PlaybackSliderView(playerManager: playerManager)
                .padding([.leading, .trailing, .bottom], 16)
        }
    }
}
