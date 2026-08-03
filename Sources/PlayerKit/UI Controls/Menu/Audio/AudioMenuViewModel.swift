import Combine
import Foundation

@MainActor
class AudioMenuViewModel: ObservableObject {
    @Published var availableAudioTracks: [TrackInfo] = []
    @Published var selectedAudio: TrackInfo?
    
    private let playerManager: PlayerManager
    init(playerManager: PlayerManager = .shared) {
        self.playerManager = playerManager

        playerManager.$availableAudioTracks
            .receive(on: RunLoop.main)
            .assign(to: &$availableAudioTracks)

        playerManager.$selectedAudio
            .receive(on: RunLoop.main)
            .assign(to: &$selectedAudio)
    }
    
    func selectAudioTrack(_ track: TrackInfo) {
        playerManager.selectAudioTrack(track: track)
    }
    
    func userInteracted() {
        playerManager.userInteracted()
    }
}
