import SwiftUI

struct PlaybackSpeedMenu: View {
    @StateObject private var viewModel: PlaybackSpeedViewModel
    
    init(playerManager: PlayerManager = .shared) {
        _viewModel = StateObject(wrappedValue: PlaybackSpeedViewModel(playerManager: playerManager))
    }

    var body: some View {
        Menu {
            Section(header: Text("Playback Speed")) {
                speedOption(0.25)
                speedOption(0.5)
                speedOption(1.0, label: "1.0x (Normal)")
                speedOption(1.25)
                speedOption(1.5)
                speedOption(2.0)
            }
        } label: {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .padding(10)
        }
        .accessibilityLabel("Playback speed")
        .accessibilityHint("Opens playback speed options")
        .accessibilityIdentifier("player.speedMenu")
        .onTapGesture {
            viewModel.userInteracted()
        }
    }

    private func speedOption(_ speed: Float, label: String? = nil) -> some View {
        Button(action: {
            viewModel.setPlaybackSpeed(speed)
        }) {
            HStack {
                Text(label ?? "\(speed)x")
                if viewModel.playbackSpeed == speed {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
}
