import SwiftUI

@MainActor
struct PlaybackSpeedMenu: View {
    static let supportedSpeeds: [Float] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    @ObservedObject private var playerManager: PlayerManager
    @StateObject private var viewModel: PlaybackSpeedViewModel
    
    init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
        _viewModel = StateObject(wrappedValue: PlaybackSpeedViewModel(playerManager: playerManager))
    }

    var body: some View {
        Menu {
            Section(header: Text(playerManager.strings.playbackSpeedTitle)) {
                ForEach(Self.supportedSpeeds, id: \.self) { speed in
                    speedOption(speed, isNormal: speed == 1)
                }
            }
        } label: {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .padding(10)
        }
        .accessibilityLabel(playerManager.strings.playbackSpeedAccessibilityLabel)
        .accessibilityHint(playerManager.strings.playbackSpeedHint)
        .accessibilityIdentifier("player.speedMenu")
        .buttonStyle(.plain)
        .onTapGesture {
            viewModel.userInteracted()
        }
    }

    private func speedOption(_ speed: Float, isNormal: Bool = false) -> some View {
        Button(action: {
            viewModel.setPlaybackSpeed(speed)
        }) {
            HStack {
                Text(playerManager.strings.playbackSpeedOption(speed, isNormal))
                if viewModel.playbackSpeed == speed {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
}
