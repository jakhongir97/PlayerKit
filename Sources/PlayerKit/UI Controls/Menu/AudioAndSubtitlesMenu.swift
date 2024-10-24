import SwiftUI

struct AudioAndSubtitlesMenu: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        Menu {
            // Audio Tracks Menu (from AudioMenu)
            AudioMenu(playerManager: playerManager)

            // Subtitle Tracks Menu (from SubtitleMenu)
            SubtitleMenu(playerManager: playerManager)

        } label: {
            Label("Audio and Subtitles", systemImage: "speaker.wave.2.bubble")
                .foregroundColor(.white)
        }
    }
}

