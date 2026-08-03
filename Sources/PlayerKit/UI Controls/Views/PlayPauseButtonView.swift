import SwiftUI

@MainActor
struct PlayPauseButtonView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        HStack {
            Button(action: {
                playerManager.isPlaybackRequested ? playerManager.pause() : playerManager.play()
                HapticsManager.shared.triggerImpactFeedback(style: .medium)
            }) {
                Image.fromFramework(
                    named: playerManager.isPlaybackRequested ? "pause" : "play",
                    fallbackSystemName: playerManager.isPlaybackRequested ? "pause.fill" : "play.fill"
                )
                    .circularGlassIcon(frameSize: PlayerKitPlatform.isDesktop ? 64 : 60)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                playerManager.isPlaybackRequested
                    ? playerManager.strings.pause
                    : playerManager.strings.play
            )
            .accessibilityHint(playerManager.strings.togglePlaybackHint)
            .accessibilityIdentifier("player.playPause")
        }
    }
}
