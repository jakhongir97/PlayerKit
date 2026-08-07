import SwiftUI

@MainActor
struct AudioMenu: View {
    @ObservedObject private var playerManager: PlayerManager
    @StateObject private var viewModel: AudioMenuViewModel
    
    init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
        _viewModel = StateObject(wrappedValue: AudioMenuViewModel(playerManager: playerManager))
    }
    
    var body: some View {
        Menu {
            Section(header: Text(playerManager.strings.audioTracksTitle)) {
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
                .playerBarGlyph()
        }
        .hidesMenuIndicatorCompat()
        .accessibilityLabel(playerManager.strings.audioTracksAccessibilityLabel)
        .accessibilityHint(playerManager.strings.audioTracksHint)
        .accessibilityIdentifier("player.audioMenu")
        .buttonStyle(.plain)
        .onTapGesture {
            viewModel.userInteracted()
        }
    }
}
