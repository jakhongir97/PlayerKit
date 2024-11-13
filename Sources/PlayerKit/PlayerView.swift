import SwiftUI

public struct PlayerView: View {
    @ObservedObject var playerManager = PlayerManager.shared

    public init(playerItem: PlayerItem) {
        playerManager.load(playerItem: playerItem)
    }

    public var body: some View {
        ZStack {
            // Full-screen PlayerRenderingView
            PlayerRenderingView()
                .id(playerManager.selectedPlayerType)
                .edgesIgnoringSafeArea(.all)

            // GestureView for handling gestures
            GestureView(gestureManager: playerManager.gestureManager)
                .zIndex(0)
                .edgesIgnoringSafeArea(.all)
            
            // Player controls
            if playerManager.areControlsVisible && !playerManager.isLocked {
                PlayerControlsView(playerManager: playerManager)
                    .transition(.opacity)
                    .zIndex(1)
            }
            
            // Lock button on the vertically centered right side
            if playerManager.areControlsVisible {
                HStack {
                    Spacer() // Push lock button to the right
                    VStack {
                        Spacer() // Center lock button vertically
                        LockButtonView()
                        Spacer() // Center lock button vertically
                    }
                }
                .zIndex(2)
            }
            
        }
        .animation(.easeInOut(duration: 0.3), value: playerManager.areControlsVisible)
        .onAppear {
            playerManager.castManager.addCastStateListener()
        }
    }
}
