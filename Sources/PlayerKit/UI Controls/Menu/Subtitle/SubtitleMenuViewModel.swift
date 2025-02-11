import Combine
import Foundation

class SubtitleMenuViewModel: ObservableObject {
    @Published var availableSubtitles: [TrackInfo] = []
    @Published var selectedSubtitle: TrackInfo?
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        let playerManager = PlayerManager.shared
        
        // Subscribe to available subtitles from PlayerManager
        playerManager.$availableSubtitles
            .receive(on: RunLoop.main)
            .assign(to: \.availableSubtitles, on: self)
            .store(in: &cancellables)
        
        // Subscribe to selected subtitle from PlayerManager
        playerManager.$selectedSubtitle
            .receive(on: RunLoop.main)
            .assign(to: \.selectedSubtitle, on: self)
            .store(in: &cancellables)
    }
    
    // Computed property to get the index of the selected subtitle
    var selectedSubtitleIndex: Int? {
        guard let selected = selectedSubtitle else { return nil }
        return availableSubtitles.firstIndex(where: { $0.id == selected.id })
    }
    
    // Function to select subtitle by index
    func selectSubtitle(index: Int?) {
        if let index = index, let track = availableSubtitles[safe: index] {
            PlayerManager.shared.selectSubtitle(track: track)
        } else {
            // User selected "Turn Off Subtitles"
            PlayerManager.shared.selectSubtitle(track: nil)
        }
    }
    
    func userInteracted() {
        PlayerManager.shared.userInteracted()
    }
}
