import SwiftUI

struct PlayerControlsView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        ZStack {
            VStack {
                // Top part: Title, description, cast button, settings menu
                TopControlsView(playerManager: playerManager)

                Spacer()

                // Middle part: Play/pause button (later: next/prev buttons)
                MiddleControlsView(playerManager: playerManager)

                Spacer()

                // Bottom part: Playback time, audio/subtitles menu, playback slider
                BottomControlsView(playerManager: playerManager)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color.black.opacity(0.5)
                    .allowsHitTesting(false)  // Ensures the background doesn't block gestures
            )
        }
    }
}
