import Combine
import Foundation

class PlayerMenuViewModel: ObservableObject {
    @Published var selectedPlayerType: PlayerType
    private let playerManager: PlayerManager

    private var cancellables = Set<AnyCancellable>()

    init(playerManager: PlayerManager = .shared) {
        self.playerManager = playerManager
        selectedPlayerType = playerManager.selectedPlayerType
        
        playerManager.$selectedPlayerType
            .receive(on: RunLoop.main)
            .assign(to: \.selectedPlayerType, on: self)
            .store(in: &cancellables)
    }

    func switchPlayer(to type: PlayerType) {
        playerManager.switchPlayer(to: type)
    }

    func userInteracted() {
        playerManager.userInteracted()
    }
}
