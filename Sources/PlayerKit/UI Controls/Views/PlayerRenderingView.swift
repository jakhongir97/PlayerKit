import SwiftUI
import AVFoundation

struct PlayerRenderingView: View {
    @ObservedObject var playerManager: PlayerManager
    
    init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
    }

    var body: some View {
        ZStack {
            if let playerView = playerManager.currentPlayer?.getPlayerView() {
                PlayerViewRepresentable(playerView: playerView)
            } else {
                Text("No video loaded.")
                    .foregroundColor(.white)
                    .accessibilityIdentifier("player.emptyState")
            }
        }
        .background(Color.black)
    }
}

#if canImport(UIKit)
struct PlayerViewRepresentable: UIViewRepresentable {
    let playerView: PKView

    func makeUIView(context: Context) -> PKView {
        playerView
    }

    func updateUIView(_ uiView: PKView, context: Context) {}
}
#else
struct PlayerViewRepresentable: NSViewRepresentable {
    let playerView: PKView

    func makeNSView(context: Context) -> PKView {
        playerView
    }

    func updateNSView(_ nsView: PKView, context: Context) {}
}
#endif
