import SwiftUI

@MainActor
struct SubtitleMenu: View {
    @StateObject private var viewModel: SubtitleMenuViewModel
    
    init(playerManager: PlayerManager = .shared) {
        _viewModel = StateObject(wrappedValue: SubtitleMenuViewModel(playerManager: playerManager))
    }
    
    var body: some View {
        Menu {
            Section(header: Text("Subtitles")) {
                // "Turn Off Subtitles" option
                Button(action: {
                    viewModel.selectSubtitle(nil)
                }) {
                    HStack {
                        Text("Turn Off")
                        if viewModel.selectedSubtitle == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                // List available subtitle tracks
                ForEach(viewModel.availableSubtitles) { track in
                    Button(action: {
                        viewModel.selectSubtitle(track)
                    }) {
                        HStack {
                            Text(track.name)
                            if viewModel.selectedSubtitle?.id == track.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "captions.bubble")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .padding(10)
        }
        .accessibilityLabel("Subtitles")
        .accessibilityHint("Opens subtitle options")
        .accessibilityIdentifier("player.subtitleMenu")
        .buttonStyle(.plain)
        .onTapGesture {
            viewModel.userInteracted()
        }
    }
}
