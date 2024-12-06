import SwiftUI

struct LockButtonView: View {
    @ObservedObject var playerManager: PlayerManager = PlayerManager.shared  // Access shared lock state
    
    // Determine if the device is an iPhone
    private var isIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    var body: some View {
        Button(action: toggleLock) {
            Image(systemName: "lock.rectangle.fill")
                .font(.system(size: 30, weight: .bold))
                .padding(5)
                .contentShape(Rectangle())
                .foregroundColor(playerManager.isLocked ? .red : .white)
                .padding(isIPhone ? 16 : 32)
                .background(Color.clear)
                .contentShape(Rectangle())
        }
    }
    
    private func toggleLock() {
        HapticsManager.shared.triggerImpactFeedback(style: .rigid)
        playerManager.isLocked.toggle()
    }
}
