import SwiftUI

public struct PlayerView: View {
    @ObservedObject var playerManager = PlayerManager.shared
    @Environment(\.presentationMode) var presentationMode

    public init(playerItem: PlayerItem? = nil) {
        playerManager.setPlayer()
        guard let playerItem = playerItem else { return }
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
            if playerManager.areControlsVisible {
                PlayerControlsView(playerManager: playerManager)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onReceive(playerManager.$shouldDissmiss) { shouldDissmiss in
            if shouldDissmiss {
                presentationMode.wrappedValue.dismiss()
                NotificationCenter.default.post(name: .PlayerKitDidClose, object: nil)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: playerManager.areControlsVisible)
    }
}
