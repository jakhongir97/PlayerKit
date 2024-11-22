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
                            Text(viewModel.availableAudioTracks[index])
                            if viewModel.selectedAudioTrackIndex == index {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "waveform.circle.fill")
                .resizable()
                .foregroundColor(.white)
                .frame(width: 25, height: 25)
        }
        .onTapGesture {
            viewModel.userInteracted()
        }
    }
}
