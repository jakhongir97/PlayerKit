import SwiftUI

@MainActor
struct BufferingIndicatorView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        if playerManager.isBuffering {
            // The other round status readout over the video — the double-tap
            // seek medallion — is glass, so this one is too. It used to be a
            // flat `black.opacity(0.62)` disc, the same value as the full-screen
            // chrome dim, which is a scrim value rather than a surface one.
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .frame(
                    width: PlayerChromeMetrics.minimumHitTarget,
                    height: PlayerChromeMetrics.minimumHitTarget
                )
                .playerGlass(.circle, appearance: playerManager.appearance)
                .accessibilityLabel(playerManager.strings.buffering)
                .accessibilityHint(playerManager.strings.bufferingHint)
                .accessibilityIdentifier("player.buffering")
        }
    }
}
