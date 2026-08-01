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
            // The visible counterpart to the double-tap skip. Without it the
            // gesture is the only way to move ten seconds, which puts it out of
            // reach of anyone who cannot perform a double tap.
            SkipButtonView(playerManager: playerManager, direction: .backward)
            Spacer()
            PlayPauseButtonView(playerManager: playerManager)
            Spacer()
            SkipButtonView(playerManager: playerManager, direction: .forward)
            Spacer()
            if playerManager.contentType == .episode {
                NextButtonView(playerManager: playerManager)
            }
            Spacer()
        }
    }
}
