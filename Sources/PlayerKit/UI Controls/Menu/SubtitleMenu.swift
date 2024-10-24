import SwiftUI

struct SubtitleMenu: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        Menu {
            ForEach(playerManager.availableSubtitles.indices, id: \.self) { index in
                Button(action: {
                    playerManager.selectSubtitle(index: index)
                }) {
                    HStack {
                        Text(playerManager.availableSubtitles[index])
                        if playerManager.selectedSubtitleTrackIndex == index {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("Subtitles", systemImage: "captions.bubble")
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
        }
    }
}
