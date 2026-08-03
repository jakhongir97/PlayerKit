import SwiftUI
import AVFoundation

@MainActor
struct PlayerRenderingView: View {
    @ObservedObject var playerManager: PlayerManager
    
    init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
    }

    var body: some View {
        ZStack {
            if hasRenderableMedia,
               let playerView = playerManager.currentPlayer?.getPlayerView() {
                ProtectedPlayerContentRepresentable(playerView: playerView)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "play.rectangle")
                        .font(.largeTitle)
                        .accessibilityHidden(true)
                    Text("No video loaded")
                        .font(.headline)
                    Text("Choose a video to begin playback.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
                    .foregroundColor(.white)
                    .padding(24)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("player.emptyState")
            }
        }
        .background(Color.black)
    }

    private var hasRenderableMedia: Bool {
        guard let player = playerManager.currentPlayer else { return false }
        if playerManager.playerItem != nil { return true }
        // Built-in backends can answer precisely. Preserve compatibility for a
        // custom preloaded backend that predates the optional capability.
        return (player as? PlayerMediaAvailabilityReporting)?.hasLoadedMedia ?? true
    }
}

#if canImport(UIKit)
@MainActor
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
@MainActor
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
