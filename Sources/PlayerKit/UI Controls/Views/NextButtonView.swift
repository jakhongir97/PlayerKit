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
            Image.fromFramework(named: "next", fallbackSystemName: "forward.end.fill")
                .circularGlassIcon(frameSize: 40, desktopHoverEnabled: !isDisabled)
                .opacity(isDisabled ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .animation(.easeInOut(duration: 0.2), value: isDisabled) // Smooth transition
        .accessibilityLabel(playerManager.strings.nextEpisodeAccessibilityLabel)
        .accessibilityHint(playerManager.strings.nextEpisodeHint)
        .accessibilityIdentifier("player.next")
    }
}
