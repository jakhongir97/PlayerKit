import SwiftUI

struct ControlMenuView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        HStack(spacing: 16) {
            PlaybackTimeView(playerManager: playerManager)

            AudioAndSubtitlesMenu(playerManager: playerManager)
        }
    }
}

