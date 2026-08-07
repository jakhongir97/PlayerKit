import SwiftUI

@MainActor
struct PrevButtonView: View {
    @ObservedObject var playerManager: PlayerManager

    private var isDisabled: Bool {
        !playerManager.canPlayPreviousItem
    }

    /// SF Symbols, not the bundled `prev`/`next` PNGs.
    ///
    /// The raster pair was drawn at one weight and one size and sat in the same
    /// row as SF Symbol glyphs that track weight and optical size, so the
    /// transport mixed two icon sets: the custom marks stayed put while the
    /// symbols around them grew and thickened with the control size.
    var body: some View {
        Button(action: {
            playerManager.playPrevious()
            HapticsManager.shared.triggerImpactFeedback(style: .light)
        }) {
            Image(systemName: "backward.end.fill")
                .playerControlIcon(
                    diameter: PlayerChromeMetrics.secondaryControlDiameter,
                    appearance: playerManager.appearance
                )
                .playerControlEnabled(!isDisabled)
        }
        .buttonStyle(PlayerControlButtonStyle(hoverEnabled: !isDisabled))
        .disabled(isDisabled)
        .accessibilityLabel(playerManager.strings.previousEpisodeAccessibilityLabel)
        .accessibilityHint(playerManager.strings.previousEpisodeHint)
        .accessibilityIdentifier("player.previous")
    }
}
