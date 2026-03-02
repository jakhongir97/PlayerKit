import SwiftUI

struct PlayerMenu: View {
    @StateObject private var viewModel: PlayerMenuViewModel
    
    init(playerManager: PlayerManager = .shared) {
        _viewModel = StateObject(wrappedValue: PlayerMenuViewModel(playerManager: playerManager))
    }

    var body: some View {
        Menu {
            ForEach(PlayerType.allCases) { playerType in
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
            Label("Player", systemImage: "shippingbox.fill")
                .padding()
                .foregroundColor(.white)
        }
        .accessibilityLabel("Player backend")
        .accessibilityHint("Selects AVPlayer or VLC backend")
        .accessibilityIdentifier("player.backendMenu")
        .onTapGesture {
            viewModel.userInteracted()
        }
    }
}
