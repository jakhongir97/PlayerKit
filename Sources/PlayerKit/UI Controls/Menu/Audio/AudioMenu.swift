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
                    PlayerMenuSelectionItem(
                        title: track.name,
                        isSelected: viewModel.selectedAudio?.id == track.id
                    ) {
                        viewModel.selectAudioTrack(track)
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
