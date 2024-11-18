import Combine
import Foundation

class PlaybackSpeedViewModel: ObservableObject {
    @Published var playbackSpeed: Float = PlayerManager.shared.playbackSpeed

    private var cancellables = Set<AnyCancellable>()

    init() {
        PlayerManager.shared.$playbackSpeed
            .receive(on: RunLoop.main)
            .assign(to: \.playbackSpeed, on: self)
            .store(in: &cancellables)
    }

    func setPlaybackSpeed(_ speed: Float) {
        PlayerManager.shared.setPlaybackSpeed(speed)
    }
    
    func userInteracted() {
        PlayerManager.shared.userInteracted()
    }
}
