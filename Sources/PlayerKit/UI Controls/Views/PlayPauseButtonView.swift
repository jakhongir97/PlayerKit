import SwiftUI

struct PlayPauseButtonView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        HStack {
            Spacer()  // Push button to the center horizontally

            Button(action: {
                playerManager.isPlaying ? playerManager.pause() : playerManager.play()
            }) {
                Image(playerManager.isPlaying ? "pause" : "play", bundle: .module)
                    .font(.system(size: 60, weight: .bold))
                    .foregroundColor(.white)
            }

            Spacer()  // Push button to the center horizontally
        }
        .frame(maxHeight: .infinity)  // Ensures it's vertically centered
    }
}

