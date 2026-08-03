import Combine
import Foundation

@MainActor
class SubtitleMenuViewModel: ObservableObject {
    @Published var availableSubtitles: [TrackInfo] = []
    @Published var selectedSubtitle: TrackInfo?
    
    private let playerManager: PlayerManager
    init(playerManager: PlayerManager = .shared) {
        self.playerManager = playerManager
        
        // Subscribe to available subtitles from PlayerManager
        playerManager.$availableSubtitles
            .receive(on: RunLoop.main)
            .assign(to: &$availableSubtitles)
        
        // Subscribe to selected subtitle from PlayerManager
        playerManager.$selectedSubtitle
            .receive(on: RunLoop.main)
            .assign(to: &$selectedSubtitle)
    }
    
    func selectSubtitle(_ track: TrackInfo?) {
        playerManager.selectSubtitle(track: track)
    }
    
    func userInteracted() {
        playerManager.userInteracted()
    }
}
