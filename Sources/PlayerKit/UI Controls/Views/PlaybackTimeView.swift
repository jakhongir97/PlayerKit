import SwiftUI

struct PlaybackTimeView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        HStack {
            Text(TimeFormatter.shared.formatTime(playerManager.isSeeking ? playerManager.seekTime : playerManager.currentTime))
                .foregroundColor(.white)

            Text("•")
                .foregroundColor(.white)

            Text(TimeFormatter.shared.formatTime(playerManager.duration))
                .foregroundColor(.white)

            if playerManager.isBuffering {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
            }
            Spacer()
        }
    }
}

