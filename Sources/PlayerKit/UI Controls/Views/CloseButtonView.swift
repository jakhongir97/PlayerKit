import SwiftUI

public struct CloseButtonView: View {
    @ObservedObject var playerManager: PlayerManager
    
    public init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
    }

    public var body: some View {
        Button(action: {
            playerManager.shouldDismiss = true
        }) {
            Image(systemName: "xmark")
                .circularGlassIcon()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close player")
        .accessibilityHint("Dismisses the player screen")
        .accessibilityIdentifier("player.close")
    }
}
