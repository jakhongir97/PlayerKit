import SwiftUI

public struct CloseButtonView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var playerManager: PlayerManager = PlayerManager.shared // Pass PlayerManager here

    public var body: some View {
        Button(action: {
            playerManager.stop() // Stop the player
            presentationMode.wrappedValue.dismiss() // Dismiss the view
        }) {
            Image(systemName: "xmark.circle.fill")
                .resizable()
                .frame(width: 30, height: 30)
                .foregroundColor(.white)
        }
        .padding(.trailing)
    }
}

