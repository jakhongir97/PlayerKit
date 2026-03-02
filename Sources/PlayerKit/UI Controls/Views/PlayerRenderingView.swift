import SwiftUI
import AVFoundation
import VLCKit

struct PlayerRenderingView: View {
    @ObservedObject var playerManager: PlayerManager
    
    init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
    }

    var body: some View {
        ZStack {
            if let playerView = playerManager.currentPlayer?.getPlayerView() {
                PlayerViewRepresentable(playerView: playerView)
            } else {
                Text("No video loaded.")
                    .foregroundColor(.white)
                    .accessibilityIdentifier("player.emptyState")
            }
        }
        .background(Color.black)
    }
}

struct PlayerViewRepresentable: UIViewRepresentable {
    let playerView: UIView

    func makeUIView(context: Context) -> UIView {
        return playerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // No need to update, since the view is managed by the player wrapper
    }
}
