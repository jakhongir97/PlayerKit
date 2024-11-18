import Combine
import Foundation

class SubtitleMenuViewModel: ObservableObject {
    @Published var availableSubtitles: [String] = []
    @Published var selectedSubtitleTrackIndex: Int?

    private var cancellables = Set<AnyCancellable>()

    init() {
        let playerManager = PlayerManager.shared

        playerManager.$availableSubtitles
            .receive(on: RunLoop.main)
            .assign(to: \.availableSubtitles, on: self)
            .store(in: &cancellables)

        playerManager.$selectedSubtitleTrackIndex
            .receive(on: RunLoop.main)
            .assign(to: \.selectedSubtitleTrackIndex, on: self)
            .store(in: &cancellables)
    }

    func selectSubtitle(index: Int?) {
        PlayerManager.shared.selectSubtitle(index: index)
    }

    func userInteracted() {
        PlayerManager.shared.userInteracted()
    }
}
