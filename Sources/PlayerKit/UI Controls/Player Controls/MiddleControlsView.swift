import SwiftUI

struct MiddleControlsView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        HStack {
            Spacer()
            if !playerManager.isMovie {
                PrevButtonView(playerManager: playerManager)
            }

            Spacer()
            PlayPauseButtonView(playerManager: playerManager)
            Spacer()
            if !playerManager.isMovie {
                NextButtonView(playerManager: playerManager)
            }
            Spacer()
        }
    }
}
