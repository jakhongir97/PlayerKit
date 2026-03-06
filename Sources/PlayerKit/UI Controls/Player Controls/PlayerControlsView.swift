import SwiftUI

struct PlayerControlsView: View {
    @ObservedObject var playerManager: PlayerManager
    
    private var isIPhone: Bool {
        PlayerKitPlatform.isPhone
    }

    var body: some View {
        ZStack {
            // Background color with opacity, ignoring safe area insets
            Color.black.opacity(0.5)
                .edgesIgnoringSafeArea(.all)
                .allowsHitTesting(false)  // Ensures the background doesn't block gestures
                .opacity(playerManager.areControlsVisible ? 1 : 0)

            VStack {
                // Top part: Title, description, cast button, settings menu
                TopControlsView(playerManager: playerManager)
                    .opacity((playerManager.isLocked || !playerManager.areControlsVisible) ? 0 : 1)

                Spacer()

                // Middle part: Play/pause button (later: next/prev buttons)
                HStack {
                    InfoButtonView(playerManager: playerManager)
                        .opacity((playerManager.isLocked || !playerManager.areControlsVisible) ? 0 : 1)
                    Spacer()
                    
                    MiddleControlsView(playerManager: playerManager)
                        .opacity((playerManager.isLocked || !playerManager.areControlsVisible) ? 0 : 1)
                    Spacer()
                    LockButtonView(playerManager: playerManager)
                        .opacity(!playerManager.areControlsVisible ? 0 : 1)
                }

                Spacer()

                // Bottom part: Playback time, audio/subtitles menu, playback slider
                VStack {
                    BottomControlsView(playerManager: playerManager)
                        .opacity((playerManager.isLocked || !playerManager.areControlsVisible) ? 0 : 1)
                    PlaybackSliderView(playerManager: playerManager)
                        .opacity(((playerManager.gestureManager.isMultipleTapping || playerManager.isSeeking || playerManager.areControlsVisible)) && !playerManager.isLocked ? 1 : 0)
                }
            }
            .padding(isIPhone ? 16 : 32)

            if !playerManager.isLocked && playerManager.shouldShowDubberCompactStatus {
                VStack {
                    HStack {
                        Spacer()

                        DubberCompactStatusView(playerManager: playerManager)
                            .opacity(playerManager.areControlsVisible ? 0 : 1)
                            .offset(y: playerManager.areControlsVisible ? -8 : 0)
                    }
                    Spacer()
                }
                .padding(isIPhone ? 16 : 32)
                .allowsHitTesting(!playerManager.areControlsVisible)
                .animation(.spring(response: 0.4, dampingFraction: 0.84), value: playerManager.areControlsVisible)
            }
        }
    }
}
