import SwiftUI

struct TopControlsView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        HStack {
            CloseButtonView()
            VStack(alignment: .leading) {
                if let title = playerManager.playerItem?.title {
                    Text(title)
                        .font(.title)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                
                if let description = playerManager.playerItem?.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            Spacer()
            
            SharingMenuView()
            SettingsMenu()
        }
    }
}

