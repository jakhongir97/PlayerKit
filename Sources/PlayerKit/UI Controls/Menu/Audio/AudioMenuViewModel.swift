import Combine
import Foundation

class AudioMenuViewModel: ObservableObject {
    @Published var availableAudioTracks: [TrackInfo] = []
    @Published var selectedAudio: TrackInfo?
    
    private let playerManager: PlayerManager
    private var cancellables = Set<AnyCancellable>()
    
    init(playerManager: PlayerManager = .shared) {
        self.playerManager = playerManager

        playerManager.$availableAudioTracks
            .receive(on: RunLoop.main)
            .assign(to: \.availableAudioTracks, on: self)
            .store(in: &cancellables)

        playerManager.$selectedAudio
            .receive(on: RunLoop.main)
            .assign(to: \.selectedAudio, on: self)
            .store(in: &cancellables)
    }
    
    // Computed property to get the index of the selected audio track
    var selectedAudioIndex: Int? {
        guard let selected = selectedAudio else { return nil }
        return availableAudioTracks.firstIndex(where: { $0.id == selected.id })
    }
    
    func selectAudioTrack(index: Int) {
        if let track = availableAudioTracks[safe: index] {
            playerManager.selectAudioTrack(track: track)
        }
    }
    
    func userInteracted() {
        playerManager.userInteracted()
    }
}
