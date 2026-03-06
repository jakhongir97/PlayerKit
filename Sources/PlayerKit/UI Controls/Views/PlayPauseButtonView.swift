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
                    .circularGlassIcon(frameSize: 60)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playerManager.isPlaying ? "Pause" : "Play")
            .accessibilityHint("Toggles playback")
            .accessibilityIdentifier("player.playPause")
        }
    }
}
