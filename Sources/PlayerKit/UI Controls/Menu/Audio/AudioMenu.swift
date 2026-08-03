import SwiftUI

@MainActor
struct AudioMenu: View {
    @StateObject private var viewModel: AudioMenuViewModel
    
    init(playerManager: PlayerManager = .shared) {
        _viewModel = StateObject(wrappedValue: AudioMenuViewModel(playerManager: playerManager))
    }
    
    var body: some View {
        Menu {
            Section(header: Text("Audio Tracks")) { // Section title
                ForEach(viewModel.availableAudioTracks) { track in
                    Button(action: {
                        viewModel.selectAudioTrack(track)
                    }) {
                        HStack {
                            Text(track.name)
                            if viewModel.selectedAudio?.id == track.id {
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
        .buttonStyle(.plain)
        .onTapGesture {
            viewModel.userInteracted()
        }
    }
}
