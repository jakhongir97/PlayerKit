import SwiftUI

struct PiPButton: View {
    @ObservedObject var playerManager: PlayerManager
    
    init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
    }

    var body: some View {
        Button(action: {
            if playerManager.isPiPActive {
                playerManager.stopPiP()
            } else {
                playerManager.startPiP()
            }
        }) {
            Image(systemName: playerManager.isPiPActive ? "pip.fill" : "pip")
                .circularGlassIcon()
                .opacity(playerManager.canTogglePiP ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!playerManager.canTogglePiP)
        .accessibilityLabel(playerManager.isPiPActive ? "Stop Picture in Picture" : "Start Picture in Picture")
        .accessibilityHint("Toggles Picture in Picture mode")
        .accessibilityIdentifier("player.pip")
    }
}
