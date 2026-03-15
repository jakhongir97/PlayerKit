import SwiftUI

struct PlayerControlsView: View {
    @ObservedObject var playerManager: PlayerManager
    
    private var isIPhone: Bool {
        PlayerKitPlatform.isPhone
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .edgesIgnoringSafeArea(.all)
                .allowsHitTesting(false)
                .opacity(playerManager.areControlsVisible ? 1 : 0)

            VStack {
                TopControlsView(playerManager: playerManager)
                    .opacity((playerManager.isLocked || !playerManager.areControlsVisible) ? 0 : 1)

                Spacer()

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

                VStack {
                    BottomControlsView(playerManager: playerManager)
                        .opacity((playerManager.isLocked || !playerManager.areControlsVisible) ? 0 : 1)
                    PlaybackSliderView(playerManager: playerManager)
                        .opacity(((playerManager.gestureManager.isMultipleTapping || playerManager.isSeeking || playerManager.areControlsVisible)) && !playerManager.isLocked ? 1 : 0)
                }
            }
            .padding(isIPhone ? 16 : 32)
            .allowsHitTesting(playerManager.areControlsVisible)
        }
    }
}
