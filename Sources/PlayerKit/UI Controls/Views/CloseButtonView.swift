import SwiftUI

public struct CloseButtonView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var playerManager: PlayerManager = PlayerManager.shared // Pass PlayerManager here

    public var body: some View {
        Button(action: {
            playerManager.shouldDissmiss = true
            presentationMode.wrappedValue.dismiss() // Dismiss the view
        }) {
            Image(systemName: "xmark")
                .circularGlassIcon()
        }
    }
}

