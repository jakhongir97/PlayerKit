import SwiftUI

struct AudioAndSubtitlesMenu: View {
    var playerManager: PlayerManager = PlayerManager.shared

    var body: some View {
        HStack(spacing: 16) {
            // Subtitle Tracks Menu
            SubtitleMenu()
            // Audio Tracks Menu
            AudioMenu()
        }
    }
}

