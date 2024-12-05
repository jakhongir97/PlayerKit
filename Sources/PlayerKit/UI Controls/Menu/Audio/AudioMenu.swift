import SwiftUI

struct AudioMenu: View {
    @ObservedObject var viewModel = AudioMenuViewModel()
    
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
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 25, weight: .bold))
                .foregroundColor(.white)
                .contentShape(Rectangle())
        }
        .onTapGesture {
            viewModel.userInteracted()
        }
    }
}
