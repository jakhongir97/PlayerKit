import SwiftUI

struct PlayPauseButtonView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        HStack {
            Button(action: {
                playerManager.isPlaybackRequested ? playerManager.pause() : playerManager.play()
                HapticsManager.shared.triggerImpactFeedback(style: .medium)
            }) {
                Image(playerManager.isPlaybackRequested ? "pause" : "play", bundle: .module)
                    .circularGlassIcon(frameSize: PlayerKitPlatform.isDesktop ? 64 : 60)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playerManager.isPlaybackRequested ? "Pause" : "Play")
            .accessibilityHint("Toggles playback")
            .accessibilityIdentifier("player.playPause")
        }
    }
}
