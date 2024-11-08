import SwiftUI

struct SubtitleMenu: View {
    var playerManager: PlayerManager = PlayerManager.shared

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
            Image(systemName: "captions.bubble.fill")
                .resizable()
                .foregroundColor(.white)
                .frame(width: 25, height: 25)
        }
        .onAppear(perform: {
            playerManager.userInteracted()
        })
        
    }
}
