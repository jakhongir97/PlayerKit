import Combine
import Foundation

class MediaOptionsMenuViewModel: ObservableObject {
    @Published var hasSubtitles: Bool = false
    @Published var hasAudioTracks: Bool = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        let playerManager = PlayerManager.shared

        // Observe availableSubtitles
        playerManager.$availableSubtitles
            .map { !$0.isEmpty }
            .receive(on: RunLoop.main)
            .assign(to: \.hasSubtitles, on: self)
            .store(in: &cancellables)

        // Observe availableAudioTracks
        playerManager.$availableAudioTracks
            .map { !$0.isEmpty }
            .receive(on: RunLoop.main)
            .assign(to: \.hasAudioTracks, on: self)
            .store(in: &cancellables)
    }
}

