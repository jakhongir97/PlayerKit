import SwiftUI

struct SettingsMenu: View {
    var playerManager: PlayerManager = PlayerManager.shared

    var body: some View {
        Menu {
            VideoMenu()

            PlaybackSpeedMenu()
            
            PlayerMenu()

        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .resizable()
                .frame(width: 25, height: 25)
                .foregroundColor(.white)
        }
        .onAppear(perform: {
            playerManager.userInteracted()
        })
    }
}


