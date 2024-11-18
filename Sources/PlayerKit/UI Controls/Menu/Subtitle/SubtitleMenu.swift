import SwiftUI

struct SubtitleMenu: View {
    @ObservedObject var viewModel = SubtitleMenuViewModel()

    var body: some View {
        Menu {
            Section(header: Text("Subtitles")) {
                // "Turn Off Subtitles" option
                Button(action: {
                    viewModel.selectSubtitle(index: nil)
                }) {
                    HStack {
                        Text("Turn off")
                        if viewModel.selectedSubtitleTrackIndex == nil {
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
                            Text(viewModel.availableSubtitles[index])
                            if viewModel.selectedSubtitleTrackIndex == index {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "captions.bubble.fill")
                .resizable()
                .foregroundColor(.white)
                .frame(width: 25, height: 25)
        }
        .onAppear {
            viewModel.userInteracted()
        }
    }
}
