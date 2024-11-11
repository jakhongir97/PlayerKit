import SwiftUI

struct AudioMenu: View {
    var playerManager: PlayerManager = PlayerManager.shared

    var body: some View {
        Menu {
            Section(header: Text("Audio Tracks")) { // Section title
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
            }
        } label: {
            Image(systemName: "waveform.circle.fill")
                .resizable()
                .foregroundColor(.white)
                .frame(width: 25, height: 25)
        }
        .onAppear(perform: {
            playerManager.userInteracted()
        })
    }
}
