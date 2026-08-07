import SwiftUI

@MainActor
struct LockButtonView: View {
    @ObservedObject var playerManager: PlayerManager
    
    init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
    }

    var body: some View {
        Button(action: toggleLock) {
            Image(systemName: playerManager.isLocked ? "lock.fill" : "lock.open")
                .playerControlIcon(appearance: playerManager.appearance)
        }
        .buttonStyle(PlayerControlButtonStyle())
        .accessibilityLabel(
            playerManager.isLocked
                ? playerManager.strings.unlockControls
                : playerManager.strings.lockControls
        )
        .accessibilityHint(playerManager.strings.lockControlsHint)
        .accessibilityIdentifier("player.lock")
    }
    
    private func toggleLock() {
        HapticsManager.shared.triggerImpactFeedback(style: .rigid)
        // Animate state change for a smooth transition
        withAnimation(.easeInOut(duration: 0.3)) {
            playerManager.isLocked.toggle()
        }
    }
}
