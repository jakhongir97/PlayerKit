import SwiftUI

struct PlayerMenuView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        Menu {
            Button(action: {
                playerManager.switchPlayer(to: .vlcPlayer)
            }) {
                HStack {
                    Text("VLC Player")
                    if playerManager.selectedPlayerType == .vlcPlayer {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Button(action: {
                playerManager.switchPlayer(to: .avPlayer)
            }) {
                HStack {
                    Text("AVPlayer")
                    if playerManager.selectedPlayerType == .avPlayer {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Image(systemName: "list.bullet")
                .padding()
                .background(Color.black.opacity(0.6))
                .clipShape(Circle())
                .foregroundColor(.white)
        }
    }
}

