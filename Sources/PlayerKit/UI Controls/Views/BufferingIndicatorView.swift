import SwiftUI

@MainActor
struct BufferingIndicatorView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        if playerManager.isBuffering {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .frame(minWidth: 44, minHeight: 44)
                .shapeBackgroundCompat(Color.black.opacity(0.62), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1))
                .accessibilityLabel(playerManager.strings.buffering)
                .accessibilityHint(playerManager.strings.bufferingHint)
                .accessibilityIdentifier("player.buffering")
        }
    }
}
