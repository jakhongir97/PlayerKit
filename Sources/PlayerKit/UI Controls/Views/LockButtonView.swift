import SwiftUI

struct LockButtonView: View {
    @ObservedObject var playerManager: PlayerManager = PlayerManager.shared  // Access shared lock state

    var body: some View {
        let isLocked = playerManager.isLocked
        
        Button(action: toggleLock) {
            HStack() {
                Image(systemName: "lock.app.dashed")
                    .hierarchicalSymbolRendering()
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(isLocked ? .red : .white)
                    .rotationEffect(.degrees(isLocked ? 0 : 360))
                    .scaleEffect(isLocked ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: isLocked)

                Text(isLocked ? "Locked" : "")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.red)
                    .transition(.slide) // Fade in/out when changing state
                    .animation(.easeInOut(duration: 0.3), value: isLocked)
            }
            .background(Color.clear)
            .padding(5)
            .contentShape(Rectangle())
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
