import Combine
import Foundation

class AudioMenuViewModel: ObservableObject {
    @Published var availableAudioTracks: [String] = []
    @Published var selectedAudioTrackIndex: Int?

    private var cancellables = Set<AnyCancellable>()

    init() {
        let playerManager = PlayerManager.shared

        playerManager.$availableAudioTracks
            .receive(on: RunLoop.main)
            .assign(to: \.availableAudioTracks, on: self)
            .store(in: &cancellables)

        playerManager.$selectedAudioTrackIndex
            .receive(on: RunLoop.main)
            .assign(to: \.selectedAudioTrackIndex, on: self)
            .store(in: &cancellables)
    }

    func selectAudioTrack(index: Int) {
        PlayerManager.shared.selectAudioTrack(index: index)
    }

    func userInteracted() {
        PlayerManager.shared.userInteracted()
    }
}

