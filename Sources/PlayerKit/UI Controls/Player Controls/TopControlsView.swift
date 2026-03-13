import SwiftUI

struct TopControlsView: View {
    @ObservedObject var playerManager: PlayerManager
    @State private var isDubberSheetPresented = false

    var body: some View {
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
            if playerManager.isDubberEnabled {
                dubbingSheetButton
            }
            SettingsMenu(playerManager: playerManager)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            if isDubberSheetPresented && playerManager.isDubberEnabled {
                VStack(spacing: 0) {
                    DubberStatusView(playerManager: playerManager)
                        .frame(maxWidth: PlayerKitPlatform.isPhone ? 248 : 264, alignment: .leading)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                .padding(.top, 72)
                .zIndex(2)
            }
        }
        .onChange(of: playerManager.areControlsVisible) { _, areControlsVisible in
            if !areControlsVisible {
                isDubberSheetPresented = false
            }
        }
        .onChange(of: playerManager.isDubberEnabled) { _, isDubberEnabled in
            if !isDubberEnabled {
                isDubberSheetPresented = false
            }
        }
    }

    private var dubbingSheetButton: some View {
        Button {
            playerManager.userInteracted()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                isDubberSheetPresented.toggle()
            }
        } label: {
            Image(systemName: dubbingIconName)
                .circularGlassIcon()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dub controls")
        .accessibilityHint("Shows dubbing controls in a floating card")
        .accessibilityIdentifier("player.dubSheet")
    }

    private var dubbingIconName: String {
        if playerManager.hasDubberIssue {
            return "exclamationmark.bubble.fill"
        }
        if playerManager.isDubLoading {
            return "waveform.badge.mic"
        }
        if playerManager.isDubbedPlaybackActive {
            return "checkmark.bubble.fill"
        }
        return "waveform.badge.mic"
    }
}
