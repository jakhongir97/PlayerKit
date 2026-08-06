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
                ProtectedPlayerContentRepresentable(
                    playerView: playerView,
                    captureMessage: playerManager.strings.videoHiddenDuringScreenSharing,
                    captureProtectionPolicy: playerManager.captureProtectionPolicy
                )
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "play.rectangle")
                        .font(.largeTitle)
                        .accessibilityHidden(true)
                    Text(playerManager.strings.noVideoLoaded)
                        .font(.headline)
                    Text(playerManager.strings.chooseVideoToBegin)
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
    let captureMessage: String
    let captureProtectionPolicy: PlayerCaptureProtectionPolicy

    func makeUIView(context: Context) -> PlayerKitProtectedContentView {
        let protectedView = PlayerKitProtectedContentView()
        protectedView.setCaptureMessage(captureMessage)
        // Before the content is installed, so `.allowCapture` parents the player
        // view outside the secure canvas on the first pass instead of moving it
        // a frame later.
        protectedView.setCaptureProtectionPolicy(captureProtectionPolicy)
        protectedView.setProtectedContentView(playerView)
        return protectedView
    }

    func updateUIView(_ uiView: PlayerKitProtectedContentView, context: Context) {
        uiView.setCaptureMessage(captureMessage)
        uiView.setCaptureProtectionPolicy(captureProtectionPolicy)
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
    let captureMessage: String
    let captureProtectionPolicy: PlayerCaptureProtectionPolicy

    func makeNSView(context: Context) -> PlayerKitProtectedContentView {
        let protectedView = PlayerKitProtectedContentView()
        protectedView.setCaptureMessage(captureMessage)
        protectedView.setCaptureProtectionPolicy(captureProtectionPolicy)
        protectedView.setProtectedContentView(playerView)
        return protectedView
    }

    func updateNSView(_ nsView: PlayerKitProtectedContentView, context: Context) {
        nsView.setCaptureMessage(captureMessage)
        nsView.setCaptureProtectionPolicy(captureProtectionPolicy)
        nsView.setProtectedContentView(playerView)
    }

    static func dismantleNSView(_ nsView: PlayerKitProtectedContentView, coordinator: ()) {
        nsView.setProtectedContentView(nil)
    }
}
#endif
