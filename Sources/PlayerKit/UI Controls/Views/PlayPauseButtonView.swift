import SwiftUI

@MainActor
struct PlayPauseButtonView: View {
    @ObservedObject var playerManager: PlayerManager

    /// Play/pause is the only control at the primary diameter. That is what
    /// makes it read as the centre of the transport — it does not need a
    /// colour, a fill, or a second material to say so.
    ///
    /// While the player buffers, the glyph gives way to a spinner inside the
    /// same disc, the way the system player's centre control does. The control
    /// stays live underneath it: pausing a stalled stream is a legitimate
    /// thing to want.
    var body: some View {
        Button(action: {
            playerManager.userDidTogglePlayback()
            HapticsManager.shared.triggerImpactFeedback(style: .medium)
        }) {
            ZStack {
                Image(systemName: playerManager.isPlaybackRequested ? "pause.fill" : "play.fill")
                    .opacity(playerManager.isBuffering ? 0 : 1)
                if playerManager.isBuffering {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
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
        .accessibilityValue(playerManager.isBuffering ? Text(playerManager.strings.buffering) : Text(""))
        .accessibilityHint(playerManager.strings.togglePlaybackHint)
        .accessibilityIdentifier("player.playPause")
    }
}
