import Combine
import Foundation

@MainActor
class PlayerMenuViewModel: ObservableObject {
    @Published var selectedPlayerType: PlayerType?
    private let playerManager: PlayerManager

    init(playerManager: PlayerManager = .shared) {
        self.playerManager = playerManager
        selectedPlayerType = playerManager.activeBuiltInPlayerType
        
        playerManager.$activeBuiltInPlayerType
            .receive(on: RunLoop.main)
            .assign(to: &$selectedPlayerType)
    }

    func switchPlayer(to type: PlayerType) {
        playerManager.switchPlayer(to: type)
    }

    func userInteracted() {
        playerManager.userInteracted()
    }
}
