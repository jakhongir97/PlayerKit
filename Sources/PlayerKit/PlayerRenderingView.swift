import SwiftUI
import AVFoundation
import VLCKit

struct PlayerRenderingView: View {
    @ObservedObject var playerManager = PlayerManager.shared

    var body: some View {
        ZStack {
            // Render AVPlayer if active and player is non-nil
            if let avPlayerWrapper = playerManager.currentPlayer as? AVPlayerWrapper,
               let avPlayer = avPlayerWrapper.player {
                AVPlayerViewRepresentable(player: avPlayer)
            }
            // Render VLCPlayer if active
            else if let vlcPlayerWrapper = playerManager.currentPlayer as? VLCPlayerWrapper {
                VLCPlayerViewRepresentable(player: vlcPlayerWrapper.player)
            }
            // Fallback if no player is loaded
            else {
                Text("No video loaded.")
                    .foregroundColor(.white)
            }
        }
    }
}


