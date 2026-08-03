import SwiftUI

@MainActor
struct SettingsMenu: View {
    private let playerManager: PlayerManager
    
    init(playerManager: PlayerManager = .shared) {
        self.playerManager = playerManager
    }

    @ViewBuilder
    var body: some View {
        #if DEBUG
        // Backend switching is a diagnostics tool, not a user setting. Keep it
        // available to developers without shipping an ellipsis that opens a
        // single implementation-detail menu in production.
        PlayerMenu(playerManager: playerManager)
        #endif
    }
}
