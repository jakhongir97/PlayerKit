import Combine
import Foundation

class SubtitleMenuViewModel: ObservableObject {
    @Published var availableSubtitles: [TrackInfo] = []
    @Published var selectedSubtitleTrackID: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        let playerManager = PlayerManager.shared
        
        // Subscribe to available subtitles from PlayerManager
        playerManager.$availableSubtitles
            .receive(on: RunLoop.main)
            .assign(to: \.availableSubtitles, on: self)
            .store(in: &cancellables)
        
        // Subscribe to selected subtitle track ID from PlayerManager
        playerManager.$selectedSubtitleTrackID
            .receive(on: RunLoop.main)
            .assign(to: \.selectedSubtitleTrackID, on: self)
            .store(in: &cancellables)
    }
    
    // Computed property to get the index of the selected subtitle
    var selectedSubtitleIndex: Int? {
        guard let selectedID = selectedSubtitleTrackID else { return nil }
        return availableSubtitles.firstIndex(where: { $0.id == selectedID })
    }
    
    // Function to select subtitle by index
    func selectSubtitle(index: Int?) {
        if let index = index, let trackID = availableSubtitles[safe: index]?.id {
            PlayerManager.shared.selectSubtitle(withID: trackID)
        } else {
            // User selected "Turn Off Subtitles"
            PlayerManager.shared.selectSubtitle(withID: nil)
        }
    }
    
    func userInteracted() {
        PlayerManager.shared.userInteracted()
    }
}
