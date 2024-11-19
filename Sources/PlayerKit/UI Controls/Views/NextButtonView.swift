import SwiftUI

struct NextButtonView: View {
    @ObservedObject var playerManager: PlayerManager

    private var isDisabled: Bool {
        playerManager.currentPlayerItemIndex == playerManager.playerItems.count - 1
    }

    var body: some View {
        Button(action: {
            playerManager.playNext()
            HapticsManager.shared.triggerImpactFeedback(style: .light)
        }) {
            Image("next", bundle: .module)
                .font(.title)
                .padding()
                .opacity(isDisabled ? 0.5 : 1.0) // Adjust alpha when disabled
        }
        .disabled(isDisabled)
        .animation(.easeInOut(duration: 0.2), value: isDisabled) // Smooth transition
    }
}

