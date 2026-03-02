import SwiftUI

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
                    viewModel.selectSubtitle(index: nil)
                }) {
                    HStack {
                        Text("Turn Off")
                        if viewModel.selectedSubtitleIndex == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                // List available subtitle tracks
                ForEach(viewModel.availableSubtitles.indices, id: \.self) { index in
                    Button(action: {
                        viewModel.selectSubtitle(index: index)
                    }) {
                        HStack {
                            Text(viewModel.availableSubtitles[index].name)
                            if viewModel.selectedSubtitleIndex == index {
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
        .onTapGesture {
            viewModel.userInteracted()
        }
    }
}
