import SwiftUI

struct LockButtonView: View {
    @ObservedObject var playerManager: PlayerManager
    
    init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
    }

    var body: some View {
        Button(action: toggleLock) {
            Image(systemName: playerManager.isLocked ? "lock.fill" : "lock.open")
                .circularGlassIcon()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playerManager.isLocked ? "Unlock controls" : "Lock controls")
        .accessibilityHint("Prevents accidental control interactions")
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
