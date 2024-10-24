import SwiftUI

struct PlaybackSpeedMenu: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        Menu {
            speedOption(0.25)
            speedOption(0.5)
            speedOption(1.0, label: "1.0x (Normal)")
            speedOption(1.25)
            speedOption(1.5)
        } label: {
            Label("Speed", systemImage: "gauge.with.dots.needle.67percent")
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
        }
    }

    private func speedOption(_ speed: Float, label: String? = nil) -> some View {
        Button(action: {
            playerManager.playbackSpeed = speed
        }) {
            HStack {
                Text(label ?? "\(speed)x")
                if playerManager.playbackSpeed == speed {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
}
