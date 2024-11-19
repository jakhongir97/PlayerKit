import SwiftUI

struct PrevButtonView: View {
    @ObservedObject var playerManager: PlayerManager

    private var isDisabled: Bool {
        playerManager.currentPlayerItemIndex == 0
    }

    var body: some View {
        Button(action: {
            playerManager.playPrevious()
            HapticsManager.shared.triggerImpactFeedback(style: .light)
        }) {
            Image("prev", bundle: .module)
                .font(.title)
                .padding()
                .opacity(isDisabled ? 0.5 : 1.0) // Adjust alpha when disabled
        }
        .disabled(isDisabled)
        .animation(.easeInOut(duration: 0.2), value: isDisabled) // Smooth transition
    }
}

