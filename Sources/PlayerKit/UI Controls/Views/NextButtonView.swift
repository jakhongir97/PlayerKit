import SwiftUI

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
            Image("next", bundle: .module)
                .circularGlassIcon(frameSize: 40, desktopHoverEnabled: !isDisabled)
                .opacity(isDisabled ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .animation(.easeInOut(duration: 0.2), value: isDisabled) // Smooth transition
        .accessibilityLabel("Next episode")
        .accessibilityHint("Plays the next episode")
        .accessibilityIdentifier("player.next")
    }
}
