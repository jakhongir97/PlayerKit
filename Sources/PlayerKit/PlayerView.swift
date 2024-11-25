import SwiftUI

public struct PlayerView: View {
    @ObservedObject var playerManager = PlayerManager.shared
    @Environment(\.presentationMode) var presentationMode

    public init(playerItem: PlayerItem) {
        playerManager.setPlayer()
        playerManager.load(playerItem: playerItem)
    }
    
    public init(playerItems: [PlayerItem], currentIndex: Int = 0) {
        playerManager.setPlayer()
        playerManager.loadEpisodes(playerItems: playerItems, currentIndex: currentIndex) // Load episodes list
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
                            .padding(.bottom , 30)
                        Spacer() // Center lock button vertically
                    }
                }
                .zIndex(2)
            }
            
        }
        .onReceive(playerManager.$shouldDissmiss) { shouldDissmiss in
            if shouldDissmiss {
                presentationMode.wrappedValue.dismiss()
                NotificationCenter.default.post(name: .PlayerKitDidClose, object: nil)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: playerManager.areControlsVisible)
        .portrait()
    }
}
