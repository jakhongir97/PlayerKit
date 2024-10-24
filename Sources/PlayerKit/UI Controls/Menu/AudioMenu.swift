import SwiftUI

struct AudioMenu: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        Menu {
            ForEach(playerManager.availableAudioTracks.indices, id: \.self) { index in
                Button(action: {
                    playerManager.selectAudioTrack(index: index)
                }) {
                    HStack {
                        Text(playerManager.availableAudioTracks[index])
                        if playerManager.selectedAudioTrackIndex == index {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("Audio", systemImage: "speaker.wave.2")
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
        }
    }
}

