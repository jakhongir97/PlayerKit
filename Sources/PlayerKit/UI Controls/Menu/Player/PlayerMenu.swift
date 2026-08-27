import SwiftUI

/// Switches between the playback backends available on this device.
@MainActor
struct PlayerMenu: View {
    @StateObject private var viewModel: PlayerMenuViewModel
    @ObservedObject private var playerManager: PlayerManager

    init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
        _viewModel = StateObject(wrappedValue: PlayerMenuViewModel(playerManager: playerManager))
    }

    var body: some View {
        Menu {
            ForEach(PlayerType.supportedCases) { playerType in
                Button {
                    viewModel.userInteracted()
                    viewModel.switchPlayer(to: playerType)
                } label: {
                    HStack {
                        Text(playerType.title(using: playerManager.strings))
                        if viewModel.selectedPlayerType == playerType {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "wrench.and.screwdriver.fill")
                .playerControlIcon(appearance: playerManager.appearance)
        }
        .hidesMenuIndicatorCompat()
        .accessibilityLabel(playerManager.strings.playbackEngineAccessibilityLabel)
        .accessibilityHint(playerManager.strings.selectPlaybackEngineHint)
        .accessibilityIdentifier("player.backendMenu")
        .buttonStyle(.plain)
    }
}
