import SwiftUI

struct PlayerMenu: View {
    @ObservedObject private var viewModel = PlayerMenuViewModel()

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
        .onTapGesture {
            viewModel.userInteracted()
        }
    }
}
