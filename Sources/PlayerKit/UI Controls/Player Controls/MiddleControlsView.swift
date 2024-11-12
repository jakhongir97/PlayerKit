import SwiftUI

struct MiddleControlsView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        HStack {
            Spacer()
            PlayPauseButtonView(playerManager: playerManager)
            Spacer()
        }
    }
}
