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
            Image(systemName: "captions.bubble.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundColor(.white)
                .padding(5)
                .contentShape(Rectangle())
        }
        .onTapGesture {
            viewModel.userInteracted()
        }
    }
}

