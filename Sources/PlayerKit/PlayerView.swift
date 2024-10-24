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
                .id(playerManager.selectedPlayerType)  // Reset on player type change
                .edgesIgnoringSafeArea(.all)

            // GestureView for handling gestures
            GestureView(gestureManager: playerManager.gestureManager)
                .zIndex(0)  // GestureView should be behind other UI elements
            
            // Player controls
            if playerManager.areControlsVisible {
                PlayerControlsView(playerManager: playerManager)
                    .transition(.opacity)
                    .zIndex(1)
            }

            // PlayerMenuView at the top-right corner
            VStack {
                HStack(spacing: 16) {
                    Spacer()
                    SharingMenuView()
                    SettingsMenu(playerManager: playerManager)
                }
                .padding()
                Spacer()
            }
            .zIndex(2)
        }
        .onAppear {
            playerManager.addCastStateListener()  // Start listening when the view appears
        }
        .onDisappear {
            playerManager.removeCastStateListener()  // Clean up listener when the view disappears
        }
    }
}
