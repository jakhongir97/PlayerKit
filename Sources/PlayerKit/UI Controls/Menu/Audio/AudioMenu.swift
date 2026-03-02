import SwiftUI

struct AudioMenu: View {
    @StateObject private var viewModel: AudioMenuViewModel
    
    init(playerManager: PlayerManager = .shared) {
        _viewModel = StateObject(wrappedValue: AudioMenuViewModel(playerManager: playerManager))
    }
    
    var body: some View {
        Menu {
            Section(header: Text("Audio Tracks")) { // Section title
                ForEach(viewModel.availableAudioTracks.indices, id: \.self) { index in
                    Button(action: {
                        viewModel.selectAudioTrack(index: index)
                    }) {
                        HStack {
                            Text(viewModel.availableAudioTracks[index].name)
                            if viewModel.selectedAudioIndex == index {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "waveform.circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .padding(10)
        }
        .accessibilityLabel("Audio tracks")
        .accessibilityHint("Opens audio track options")
        .accessibilityIdentifier("player.audioMenu")
        .onTapGesture {
            viewModel.userInteracted()
        }
    }
}
