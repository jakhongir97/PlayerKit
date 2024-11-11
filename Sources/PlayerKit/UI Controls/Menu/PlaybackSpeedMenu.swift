import SwiftUI

struct PlaybackSpeedMenu: View {
    @ObservedObject var playerManager: PlayerManager = PlayerManager.shared

    var body: some View {
        Menu {
            Section(header: Text("Playback Speed")) { // Section title
                speedOption(0.25)
                speedOption(0.5)
                speedOption(1.0, label: "1.0x (Normal)")
                speedOption(1.25)
                speedOption(1.5)
            }
        } label: {
            Image(systemName: "gauge.with.needle.fill")
                .resizable()
                .foregroundColor(.white)
                .frame(width: 25, height: 25)
        }
        .onAppear(perform: {
            playerManager.userInteracted()
        })
    }

    private func speedOption(_ speed: Float, label: String? = nil) -> some View {
        Button(action: {
            playerManager.setPlaybackSpeed(speed)
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
