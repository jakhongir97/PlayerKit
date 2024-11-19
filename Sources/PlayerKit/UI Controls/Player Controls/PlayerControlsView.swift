import SwiftUI

struct PlayerControlsView: View {
    @ObservedObject var playerManager: PlayerManager
    
    // Determine if the device is an iPhone
    private var isIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    var body: some View {
        ZStack {
            // Background color with opacity, ignoring safe area insets
            Color.black.opacity(0.5)
                .edgesIgnoringSafeArea(.all)
                .allowsHitTesting(false)  // Ensures the background doesn't block gestures

            VStack {
                // Top part: Title, description, cast button, settings menu
                TopControlsView(playerManager: playerManager)

                Spacer()

                // Middle part: Play/pause button (later: next/prev buttons)
                MiddleControlsView(playerManager: playerManager)
                    .padding(.top, 20)

                Spacer()

                // Bottom part: Playback time, audio/subtitles menu, playback slider
                BottomControlsView(playerManager: playerManager)
            }
            .padding(isIPhone ? 16 : 32)
        }
    }
}
