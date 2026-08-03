import SwiftUI

@MainActor
struct PlayerMenu: View {
    @StateObject private var viewModel: PlayerMenuViewModel
    
    init(playerManager: PlayerManager = .shared) {
        _viewModel = StateObject(wrappedValue: PlayerMenuViewModel(playerManager: playerManager))
    }

    var body: some View {
        Menu {
            ForEach(PlayerType.supportedCases) { playerType in
                Button(action: {
                    viewModel.switchPlayer(to: playerType)
                }) {
                    HStack {
                        Text(playerType.title)
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
        .accessibilityLabel("Playback engine")
        .accessibilityHint(
            PlayerType.supportedCases.count > 1
                ? Text("Selects a playback engine for debugging")
                : Text("Shows the active playback engine")
        )
        .accessibilityIdentifier("player.debug.backendMenu")
        .buttonStyle(.plain)
        .onTapGesture {
            viewModel.userInteracted()
        }
    }
}
