import SwiftUI

struct DubberButton: View {
    @ObservedObject var playerManager: PlayerManager

    init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
    }

    var body: some View {
        Button {
            playerManager.userInteracted()
            Task {
                await playerManager.startDubbedPlayback()
            }
        } label: {
            Image(systemName: playerManager.isDubLoading ? "hourglass" : "mic.fill")
                .circularGlassIcon()
        }
        .disabled(!playerManager.canStartDubbedPlayback)
        .opacity(playerManager.canStartDubbedPlayback ? 1 : 0.6)
        .accessibilityLabel(playerManager.isDubLoading ? "Generating dubbed stream" : "Dub current stream")
        .accessibilityHint("Creates a dubbed HLS stream for the current media")
        .accessibilityIdentifier("player.dub")
    }
}
