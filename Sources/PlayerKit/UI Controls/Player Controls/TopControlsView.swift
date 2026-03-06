import SwiftUI

struct TopControlsView: View {
    @ObservedObject var playerManager: PlayerManager
    private var isPhone: Bool { PlayerKitPlatform.isPhone }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CloseButtonView(playerManager: playerManager)
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
                SettingsMenu(playerManager: playerManager)
            }

            if playerManager.isDubberEnabled {
                DubberStatusView(playerManager: playerManager)
                    .frame(maxWidth: isPhone ? .infinity : 440, alignment: .leading)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}
