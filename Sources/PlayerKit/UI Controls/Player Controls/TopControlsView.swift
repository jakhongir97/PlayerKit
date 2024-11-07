import SwiftUI

struct TopControlsView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Title")
                    .font(.title)
                    .bold()
                    .foregroundColor(.white)
                
                Text("Description")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            Spacer()
            
            SharingMenuView()
            SettingsMenu(playerManager: playerManager)
        }
    }
}

