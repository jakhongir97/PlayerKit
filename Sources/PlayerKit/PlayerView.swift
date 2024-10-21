import SwiftUI
import AVFoundation

public struct PlayerView: View {
    @ObservedObject var playerManager = PlayerManager.shared

    public init() {}

    public var body: some View {
        ZStack {
            renderPlayerView()  // Video rendering

            GestureView(gestureManager: playerManager.gestureManager)
                .allowsHitTesting(true)
                .zIndex(0)

            if playerManager.areControlsVisible {
                PlayerControlsView(playerManager: playerManager)  // Separated controls UI block with new name
                    .transition(.opacity)  // Smoothly show/hide controls
                    .zIndex(1)
            }
        }
        .edgesIgnoringSafeArea(.all)
    }

    @ViewBuilder
    func renderPlayerView() -> some View {
        PlayerRenderingView()
            .background(Color.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
