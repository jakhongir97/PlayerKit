import Combine
import Foundation

@MainActor
class PlaybackSpeedViewModel: ObservableObject {
    @Published var playbackSpeed: Float
    private let playerManager: PlayerManager

    init(playerManager: PlayerManager = .shared) {
        self.playerManager = playerManager
        playbackSpeed = playerManager.playbackSpeed
        
        playerManager.$playbackSpeed
            .receive(on: RunLoop.main)
            .assign(to: &$playbackSpeed)
    }

    func setPlaybackSpeed(_ speed: Float) {
        playerManager.setPlaybackSpeed(speed)
    }
    
    func userInteracted() {
        playerManager.userInteracted()
    }
}
