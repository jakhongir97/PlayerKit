import SwiftUI

@MainActor
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
                .playerControlIcon(appearance: playerManager.appearance)
        }
        .buttonStyle(PlayerControlButtonStyle())
        .accessibilityLabel(playerManager.strings.closePlayer)
        .accessibilityHint(playerManager.strings.closePlayerHint)
        .accessibilityIdentifier("player.close")
    }
}
