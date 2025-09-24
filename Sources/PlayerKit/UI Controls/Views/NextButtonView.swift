import SwiftUI

struct NextButtonView: View {
    @ObservedObject var playerManager: PlayerManager

    private var isDisabled: Bool {
        false
    }

    var body: some View {
        Button(action: {
            playerManager.playNext()
            HapticsManager.shared.triggerImpactFeedback(style: .light)
        }) {
            Image("next", bundle: .module)
                .circularGlassIcon(frameSize: 40)
                .opacity(isDisabled ? 0.5 : 1.0)
        }
        .disabled(isDisabled)
        .animation(.easeInOut(duration: 0.2), value: isDisabled) // Smooth transition
    }
}

