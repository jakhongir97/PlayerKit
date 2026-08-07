import SwiftUI

@MainActor
struct PlayPauseButtonView: View {
    @ObservedObject var playerManager: PlayerManager

    /// Play/pause is the only control at the primary diameter. That is what
    /// makes it read as the centre of the transport — it does not need a
    /// colour, a fill, or a second material to say so.
    var body: some View {
        Button(action: {
            playerManager.isPlaybackRequested ? playerManager.pause() : playerManager.play()
            HapticsManager.shared.triggerImpactFeedback(style: .medium)
        }) {
            Image(systemName: playerManager.isPlaybackRequested ? "pause.fill" : "play.fill")
                .playerControlIcon(
                    diameter: PlayerChromeMetrics.primaryControlDiameter,
                    appearance: playerManager.appearance
                )
        }
        .buttonStyle(PlayerControlButtonStyle())
        .accessibilityLabel(
            playerManager.isPlaybackRequested
                ? playerManager.strings.pause
                : playerManager.strings.play
        )
        .accessibilityHint(playerManager.strings.togglePlaybackHint)
        .accessibilityIdentifier("player.playPause")
    }
}
