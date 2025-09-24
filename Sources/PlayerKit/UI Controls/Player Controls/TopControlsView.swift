import SwiftUI

struct TopControlsView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        HStack {
            CloseButtonView()
            VStack(alignment: .leading) {
                if let title = playerManager.playerItem?.title {
                    Text(title)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                
                if let description = playerManager.playerItem?.description {
                    Text(description)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal)
            Spacer()
            
            SharingMenuView()
            SettingsMenu()
        }
    }
}

