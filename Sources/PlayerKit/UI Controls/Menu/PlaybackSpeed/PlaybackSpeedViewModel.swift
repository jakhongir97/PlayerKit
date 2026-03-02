import Combine
import Foundation

class PlaybackSpeedViewModel: ObservableObject {
    @Published var playbackSpeed: Float
    private let playerManager: PlayerManager

    private var cancellables = Set<AnyCancellable>()

    init(playerManager: PlayerManager = .shared) {
        self.playerManager = playerManager
        playbackSpeed = playerManager.playbackSpeed
        
        playerManager.$playbackSpeed
            .receive(on: RunLoop.main)
            .assign(to: \.playbackSpeed, on: self)
            .store(in: &cancellables)
    }

    func setPlaybackSpeed(_ speed: Float) {
        playerManager.setPlaybackSpeed(speed)
    }
    
    func userInteracted() {
        playerManager.userInteracted()
    }
}
