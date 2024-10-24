import SwiftUI

struct SettingsMenu: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        Menu {
            VideoMenu(playerManager: playerManager)

            PlaybackSpeedMenu(playerManager: playerManager)
            
            PlayerMenu(playerManager: playerManager)

        } label: {
            Image(systemName: "gearshape")
                .foregroundColor(.white)
        }
    }
}


