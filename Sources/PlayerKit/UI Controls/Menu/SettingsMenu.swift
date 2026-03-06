import SwiftUI

struct SettingsMenu: View {
    private let playerManager: PlayerManager
    
    init(playerManager: PlayerManager = .shared) {
        self.playerManager = playerManager
    }

    var body: some View {
        Menu {
            PlayerMenu(playerManager: playerManager)

        } label: {
            Image(systemName: "ellipsis")
                .circularGlassIcon()
        }
        .accessibilityLabel("Settings")
        .accessibilityHint("Opens player settings")
        .accessibilityIdentifier("player.settingsMenu")
        .buttonStyle(.plain)
        .onTapGesture {
            playerManager.userInteracted()
        }
    }
}
