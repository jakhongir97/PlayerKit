import SwiftUI

struct PlayerMenu: View {
    var playerManager: PlayerManager = PlayerManager.shared

    var body: some View {
        Menu {
            Button(action: {
                playerManager.switchPlayer(to: .vlcPlayer)
            }) {
                HStack {
                    Text(PlayerType.vlcPlayer.title)
                    if playerManager.selectedPlayerType == .vlcPlayer {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Button(action: {
                playerManager.switchPlayer(to: .avPlayer)
            }) {
                HStack {
                    Text(PlayerType.avPlayer.title)
                    if playerManager.selectedPlayerType == .avPlayer {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Label("Player", systemImage: "shippingbox.fill")
                .padding()
                .foregroundColor(.white)
        }
    }
}

