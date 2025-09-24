import SwiftUI

struct LockButtonView: View {
    @ObservedObject var playerManager: PlayerManager = PlayerManager.shared  // Access shared lock state

    var body: some View {
        let isLocked = playerManager.isLocked
        
        Button(action: toggleLock) {
            Image(systemName: "lock")
                .circularGlassIcon()
        }
    }
    
    private func toggleLock() {
        HapticsManager.shared.triggerImpactFeedback(style: .rigid)
        // Animate state change for a smooth transition
        withAnimation(.easeInOut(duration: 0.3)) {
            playerManager.isLocked.toggle()
        }
    }
}
