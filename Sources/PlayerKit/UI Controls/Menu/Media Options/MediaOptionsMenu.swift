import SwiftUI

struct MediaOptionsMenu: View {
    @StateObject private var viewModel = MediaOptionsMenuViewModel()

    var body: some View {
        HStack() {
            PlaybackSpeedMenu()

            // Conditionally include SubtitleMenu
            if viewModel.hasSubtitles {
                SubtitleMenu()
            }

            // Conditionally include AudioMenu
            if viewModel.hasAudioTracks {
                AudioMenu()
            }
        }
    }
}
