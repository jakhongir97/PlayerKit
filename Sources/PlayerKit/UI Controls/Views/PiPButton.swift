import SwiftUI

struct PiPButton: View {
    @ObservedObject var playerManager = PlayerManager.shared  // Observe PlayerManager's PiP state

    var body: some View {
        Button(action: {
            if playerManager.isPiPActive {
                playerManager.stopPiP()  // Stop PiP if it's active
            } else {
                playerManager.startPiP()  // Start PiP if it's not active
            }
        }) {
            // Change the image based on whether PiP is active
            Image(systemName: playerManager.isPiPActive ? "pip.fill" : "pip")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(.white)
                .padding(5)
                .contentShape(Rectangle())
        }
    }
}

