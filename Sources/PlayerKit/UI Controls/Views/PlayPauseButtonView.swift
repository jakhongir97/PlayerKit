import SwiftUI

struct PlayPauseButtonView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        HStack {
            Button(action: {
                playerManager.isPlaying ? playerManager.pause() : playerManager.play()
                HapticsManager.shared.triggerImpactFeedback(style: .medium)
            }) {
                Image(playerManager.isPlaying ? "pause" : "play", bundle: .module)
                    .font(.system(size: 60, weight: .light))
                    .foregroundColor(.white)
            }
        }
    }
}

