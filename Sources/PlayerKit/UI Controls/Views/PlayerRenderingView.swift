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
                ProtectedPlayerContentRepresentable(playerView: playerView)
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
struct ProtectedPlayerContentRepresentable: UIViewRepresentable {
    let playerView: PKView

    func makeUIView(context: Context) -> PlayerKitProtectedContentView {
        let protectedView = PlayerKitProtectedContentView()
        protectedView.setProtectedContentView(playerView)
        return protectedView
    }

    func updateUIView(_ uiView: PlayerKitProtectedContentView, context: Context) {
        uiView.setProtectedContentView(playerView)
    }

    static func dismantleUIView(_ uiView: PlayerKitProtectedContentView, coordinator: ()) {
        uiView.setProtectedContentView(nil)
    }
}
#else
struct ProtectedPlayerContentRepresentable: NSViewRepresentable {
    let playerView: PKView

    func makeNSView(context: Context) -> PlayerKitProtectedContentView {
        let protectedView = PlayerKitProtectedContentView()
        protectedView.setProtectedContentView(playerView)
        return protectedView
    }

    func updateNSView(_ nsView: PlayerKitProtectedContentView, context: Context) {
        nsView.setProtectedContentView(playerView)
    }

    static func dismantleNSView(_ nsView: PlayerKitProtectedContentView, coordinator: ()) {
        nsView.setProtectedContentView(nil)
    }
}
#endif
