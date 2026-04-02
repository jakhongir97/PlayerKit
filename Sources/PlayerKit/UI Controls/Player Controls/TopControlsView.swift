import SwiftUI

struct TopControlsView: View {
    @ObservedObject var playerManager: PlayerManager
    @State private var isDubberSheetPresented = false
    @State private var isDubberButtonPulsing = false

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
        .overlay(dubberSheetOverlay, alignment: .topTrailing)
        .onAppear {
            isDubberButtonPulsing.toggle()
        }
        .compatOnChange(of: playerManager.areControlsVisible) { areControlsVisible in
            if !areControlsVisible && !playerManager.isDubberSheetPinned {
                isDubberSheetPresented = false
            }
        }
        .compatOnChange(of: playerManager.isDubberEnabled) { isDubberEnabled in
            if !isDubberEnabled {
                playerManager.releaseDubberSheetPin()
                isDubberSheetPresented = false
            }
        }
        .compatOnChange(of: playerManager.isDubLoading) { isDubLoading in
            guard playerManager.isDubberEnabled else { return }
            if isDubLoading {
                presentDubberSheet()
                isDubberButtonPulsing.toggle()
            }
        }
        .compatOnChange(of: playerManager.isDubbedPlaybackActive) { isDubbedPlaybackActive in
            if isDubbedPlaybackActive {
                presentDubberSheet()
                playerManager.releaseDubberSheetPin()
                isDubberButtonPulsing.toggle()
            }
        }
        .compatOnChange(of: playerManager.hasDubberIssue) { hasDubberIssue in
            if hasDubberIssue {
                presentDubberSheet()
                isDubberButtonPulsing.toggle()
            }
        }
        .compatOnChange(of: playerManager.dubSessionID) { dubSessionID in
            if dubSessionID == nil
                && !playerManager.isDubLoading
                && !playerManager.isDubbedPlaybackActive
                && !playerManager.hasDubberIssue {
                playerManager.releaseDubberSheetPin()
                dismissDubberSheet()
            }
        }
    }

    private var dubbingSheetButton: some View {
        Button {
            playerManager.userInteracted()
            if isDubberSheetPresented {
                playerManager.releaseDubberSheetPin()
                dismissDubberSheet()
            } else {
                presentDubberSheet()
            }
        } label: {
            ZStack {
                if showsDubberButtonGlow {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    dubberButtonGlowColor.opacity(shouldAnimateDubberButton ? 0.34 : 0.24),
                                    dubberButtonGlowColor.opacity(0.08),
                                    .clear,
                                ],
                                center: .center,
                                startRadius: 8,
                                endRadius: 34
                            )
                        )
                        .frame(width: 76, height: 76)
                        .blur(radius: shouldAnimateDubberButton ? 8 : 12)
                        .scaleEffect(shouldAnimateDubberButton ? (isDubberButtonPulsing ? 1.12 : 0.88) : 0.96)

                    Circle()
                        .stroke(dubberButtonGlowColor.opacity(0.34), lineWidth: 1)
                        .frame(width: 54, height: 54)
                        .scaleEffect(shouldAnimateDubberButton ? (isDubberButtonPulsing ? 1.18 : 0.92) : 1.02)
                }

                Image(systemName: dubbingIconName)
                    .circularGlassIcon()
            }
            .animation(
                shouldAnimateDubberButton
                    ? .easeInOut(duration: 1.25).repeatForever(autoreverses: true)
                    : .spring(response: 0.32, dampingFraction: 0.86),
                value: isDubberButtonPulsing
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dub controls")
        .accessibilityHint("Shows dubbing controls in a floating card")
        .accessibilityIdentifier("player.dubSheet")
    }

    @ViewBuilder
    private var dubberSheetOverlay: some View {
        if isDubberSheetPresented && playerManager.isDubberEnabled {
            VStack(spacing: 0) {
                DubberStatusView(playerManager: playerManager)
                    .frame(maxWidth: PlayerKitPlatform.isPhone ? 280 : 312, alignment: .leading)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            .padding(.top, 72)
            .zIndex(2)
        }
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

    private var shouldAnimateDubberButton: Bool {
        playerManager.dubberVisualState == .loading || playerManager.dubberVisualState == .error
    }

    private var showsDubberButtonGlow: Bool {
        playerManager.dubberVisualState != .idle
    }

    private var dubberButtonGlowColor: Color {
        switch playerManager.dubberVisualState {
        case .error:
            return Color(red: 0.97, green: 0.45, blue: 0.40)
        case .live:
            return Color(red: 0.34, green: 0.90, blue: 0.62)
        case .settling:
            return Color(red: 0.72, green: 0.94, blue: 0.78)
        case .loading:
            return Color(red: 0.22, green: 0.82, blue: 0.98)
        case .idle:
            return Color.white.opacity(0.3)
        }
    }

    private func presentDubberSheet() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            isDubberSheetPresented = true
        }
    }

    private func dismissDubberSheet() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.90)) {
            isDubberSheetPresented = false
        }
    }
}
