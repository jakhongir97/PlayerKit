import SwiftUI

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
                Button(action: {
                    viewModel.switchPlayer(to: playerType)
                }) {
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
                .circularGlassIcon()
        }
        .accessibilityLabel(playerManager.strings.playbackEngineAccessibilityLabel)
        .accessibilityHint(
            PlayerType.supportedCases.count > 1
                ? Text(playerManager.strings.selectPlaybackEngineHint)
                : Text(playerManager.strings.activePlaybackEngineHint)
        )
        .accessibilityIdentifier("player.debug.backendMenu")
        .buttonStyle(.plain)
        .onTapGesture {
            viewModel.userInteracted()
        }
    }
}
