import Combine
import Foundation

class AudioMenuViewModel: ObservableObject {
    @Published var availableAudioTracks: [TrackInfo] = []
    @Published var selectedAudioTrackID: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        let playerManager = PlayerManager.shared
        
        playerManager.$availableAudioTracks
            .receive(on: RunLoop.main)
            .assign(to: \.availableAudioTracks, on: self)
            .store(in: &cancellables)
        
        playerManager.$selectedAudioTrackID
            .receive(on: RunLoop.main)
            .assign(to: \.selectedAudioTrackID, on: self)
            .store(in: &cancellables)
    }
    
    // Computed property to get the index of the selected audio track
    var selectedAudioIndex: Int? {
        guard let selectedID = selectedAudioTrackID else { return nil }
        return availableAudioTracks.firstIndex(where: { $0.id == selectedID })
    }
    
    func selectAudioTrack(index: Int) {
        if let trackID = availableAudioTracks[safe: index]?.id {
            PlayerManager.shared.selectAudioTrack(withID: trackID)
        }
    }
    
    func userInteracted() {
        PlayerManager.shared.userInteracted()
    }
}
