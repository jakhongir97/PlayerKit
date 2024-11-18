import Combine
import Foundation

class PlayerMenuViewModel: ObservableObject {
    @Published var selectedPlayerType: PlayerType = PlayerManager.shared.selectedPlayerType

    private var cancellables = Set<AnyCancellable>()

    init() {
        PlayerManager.shared.$selectedPlayerType
            .receive(on: RunLoop.main)
            .assign(to: \.selectedPlayerType, on: self)
            .store(in: &cancellables)
    }

    func switchPlayer(to type: PlayerType) {
        PlayerManager.shared.switchPlayer(to: type)
    }

    func userInteracted() {
        PlayerManager.shared.userInteracted()
    }
}

