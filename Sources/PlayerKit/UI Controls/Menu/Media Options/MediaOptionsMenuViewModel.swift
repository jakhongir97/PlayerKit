import Combine
import Foundation

@MainActor
class MediaOptionsMenuViewModel: ObservableObject {
    @Published var hasSubtitles: Bool = false
    @Published var hasAudioTracks: Bool = false

    private let playerManager: PlayerManager
    init(playerManager: PlayerManager = .shared) {
        self.playerManager = playerManager

        // Observe availableSubtitles
        playerManager.$availableSubtitles
            .map { !$0.isEmpty }
            .receive(on: RunLoop.main)
            .assign(to: &$hasSubtitles)

        // Observe availableAudioTracks
        playerManager.$availableAudioTracks
            .map { !$0.isEmpty }
            .receive(on: RunLoop.main)
            .assign(to: &$hasAudioTracks)
    }
}
