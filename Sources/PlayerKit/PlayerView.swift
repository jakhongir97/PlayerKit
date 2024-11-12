import SwiftUI

public struct PlayerView: View {
    @ObservedObject var playerManager = PlayerManager.shared

    public init() {
        playerManager.setPlayer(type: playerManager.selectedPlayerType)
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
            
            // Lock button in the top-left corner
            if playerManager.areControlsVisible {
                VStack {
                    HStack {
                        LockButtonView()
                            .padding(.leading) // Adjust padding as needed
                            .padding(.top, 80)
                        Spacer()
                    }
                    Spacer()
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
