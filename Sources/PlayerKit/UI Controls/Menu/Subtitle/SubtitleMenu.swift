import SwiftUI

@MainActor
struct SubtitleMenu: View {
    @ObservedObject private var playerManager: PlayerManager
    @StateObject private var viewModel: SubtitleMenuViewModel
    
    init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
        _viewModel = StateObject(wrappedValue: SubtitleMenuViewModel(playerManager: playerManager))
    }
    
    var body: some View {
        Menu {
            Section(header: Text(playerManager.strings.subtitles)) {
                // "Turn Off Subtitles" option
                PlayerMenuSelectionItem(
                    title: playerManager.strings.turnOffSubtitles,
                    isSelected: viewModel.selectedSubtitle == nil
                ) {
                    viewModel.selectSubtitle(nil)
                }

                // List available subtitle tracks
                ForEach(viewModel.availableSubtitles) { track in
                    PlayerMenuSelectionItem(
                        title: track.name,
                        isSelected: viewModel.selectedSubtitle?.id == track.id
                    ) {
                        viewModel.selectSubtitle(track)
                    }
                }
            }
        } label: {
            Image(systemName: "captions.bubble")
                .playerBarGlyph()
        }
        .hidesMenuIndicatorCompat()
        .accessibilityLabel(playerManager.strings.subtitles)
        .accessibilityHint(playerManager.strings.subtitlesHint)
        .accessibilityIdentifier("player.subtitleMenu")
        .buttonStyle(.plain)
        .onTapGesture {
            viewModel.userInteracted()
        }
    }
}
