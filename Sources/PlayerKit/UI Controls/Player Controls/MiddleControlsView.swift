import SwiftUI

struct MiddleControlsView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        HStack {
            Spacer()
            if playerManager.contentType == .episode {
                PrevButtonView(playerManager: playerManager)
            }

            Spacer()
            PlayPauseButtonView(playerManager: playerManager)
            Spacer()
            if playerManager.contentType == .episode {
                NextButtonView(playerManager: playerManager)
            }
            Spacer()
        }
    }
}
