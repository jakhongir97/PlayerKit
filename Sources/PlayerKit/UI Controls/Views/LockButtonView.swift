import SwiftUI

struct LockButtonView: View {
    @ObservedObject var playerManager: PlayerManager = PlayerManager.shared  // Access shared lock state
    
    // Determine if the device is an iPhone
    private var isIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    var body: some View {
        Button(action: toggleLock) {
            HStack(spacing: 8) {
                if playerManager.isLocked {
                    Text("Unlock")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(10)
                }
                Image(systemName: playerManager.isLocked ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(playerManager.isLocked ? .red : .white)
            }
            .padding(isIPhone ? 16 : 32)
            .background(Color.clear)
            .contentShape(Rectangle())
        }
    }
    
    private func toggleLock() {
        playerManager.isLocked.toggle()
    }
}
