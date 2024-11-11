import SwiftUI

struct VideoMenu: View {
    @ObservedObject var playerManager: PlayerManager = PlayerManager.shared

    var body: some View {
        Menu {
            ForEach(playerManager.availableVideoTracks.indices, id: \.self) { index in
                Button(action: {
                    playerManager.selectVideoTrack(index: index)
                }) {
                    HStack {
                        Text(playerManager.availableVideoTracks[index])
                        if playerManager.selectedVideoTrackIndex == index {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("Video", systemImage: "play.square.stack")
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
        }
    }
}
