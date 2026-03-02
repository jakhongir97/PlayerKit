import SwiftUI

struct PiPButton: View {
    @ObservedObject var playerManager: PlayerManager
    
    init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
    }

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
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .padding(10)
        }
        .accessibilityLabel(playerManager.isPiPActive ? "Stop Picture in Picture" : "Start Picture in Picture")
        .accessibilityHint("Toggles Picture in Picture mode")
        .accessibilityIdentifier("player.pip")
    }
}
