import SwiftUI

public struct CloseButtonView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var playerManager: PlayerManager
    
    public init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
    }

    public var body: some View {
        Button(action: {
            playerManager.shouldDismiss = true
            presentationMode.wrappedValue.dismiss() // Dismiss the view
        }) {
            Image(systemName: "xmark")
                .circularGlassIcon()
        }
        .accessibilityLabel("Close player")
        .accessibilityHint("Dismisses the player screen")
        .accessibilityIdentifier("player.close")
    }
}
