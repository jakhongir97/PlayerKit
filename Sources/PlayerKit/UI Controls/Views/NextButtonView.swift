import SwiftUI

@MainActor
struct NextButtonView: View {
    @ObservedObject var playerManager: PlayerManager

    private var isDisabled: Bool {
        !playerManager.canPlayNextItem
    }

    var body: some View {
        Button(action: {
            playerManager.playNext()
            HapticsManager.shared.triggerImpactFeedback(style: .light)
        }) {
            Image(systemName: "forward.end.fill")
                .playerControlIcon(
                    diameter: PlayerChromeMetrics.secondaryControlDiameter,
                    appearance: playerManager.appearance
                )
                .playerControlEnabled(!isDisabled)
        }
        .buttonStyle(PlayerControlButtonStyle(hoverEnabled: !isDisabled))
        .disabled(isDisabled)
        .accessibilityLabel(playerManager.strings.nextEpisodeAccessibilityLabel)
        .accessibilityHint(playerManager.strings.nextEpisodeHint)
        .accessibilityIdentifier("player.next")
    }
}
