import SwiftUI

@MainActor
struct BottomControlsView: View {
    @ObservedObject var playerManager: PlayerManager
    let presentationPolicy: PlayerPresentationPolicy

    private var isIPhone: Bool { PlayerKitPlatform.isPhone }
    private let pillInsets = EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
    private var showsPiP: Bool { playerManager.isPiPSupported }
    private var showsRotate: Bool { isIPhone }
    private var showsFullscreen: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }
    private var showsTrailingIconActions: Bool {
        showsPiP || showsRotate || showsFullscreen
    }
    private var shouldGroupTrailingIconActions: Bool {
        [showsPiP, showsRotate, showsFullscreen].filter { $0 }.count > 1
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            ViewThatFits(in: .horizontal) {
                regularLayout
                    .fixedSize(horizontal: true, vertical: false)
                compactLayout
            }
        } else {
            // iOS 15 has no proposal-aware ViewThatFits. Two rows retain every
            // action and target size without guessing which device owns a
            // compact embedded player.
            compactLayout
        }
    }

    private var regularLayout: some View {
        HStack(spacing: 12) {
            LiveStatusView(playerManager: playerManager)
            MediaOptionsMenu(
                playerManager: playerManager,
                presentationPolicy: presentationPolicy
            )
            SkipIntroButtonView(playerManager: playerManager)

            Spacer()

            SkipOutroButtonView(playerManager: playerManager)

            if showsTrailingIconActions {
                if shouldGroupTrailingIconActions {
                    groupedTrailingIconActions
                } else {
                    ungroupedTrailingIconActions
                }
            }
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 8) {
            if showsCompactLiveStatusRow {
                HStack {
                    LiveStatusView(playerManager: playerManager)
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 12) {
                MediaOptionsMenu(
                    playerManager: playerManager,
                    presentationPolicy: presentationPolicy
                )
                Spacer(minLength: 8)
                trailingIconActions
            }

            HStack(spacing: 8) {
                SkipIntroButtonView(playerManager: playerManager)
                Spacer(minLength: 8)
                SkipOutroButtonView(playerManager: playerManager)
            }
        }
    }

    var showsCompactLiveStatusRow: Bool {
        playerManager.isAtLiveEdge != nil
    }

    @ViewBuilder
    private var trailingIconActions: some View {
        if showsTrailingIconActions {
            if shouldGroupTrailingIconActions {
                groupedTrailingIconActions
            } else {
                ungroupedTrailingIconActions
            }
        }
    }

    @ViewBuilder
    private var trailingActionsContent: some View {
        HStack {
            if showsPiP {
                PiPButton(playerManager: playerManager)
            }
            if showsRotate {
                RotateButtonView(playerManager: playerManager)
            }
            if showsFullscreen {
                FullscreenButtonView(playerManager: playerManager)
            }
        }
    }

    @ViewBuilder
    private var groupedTrailingIconActions: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer {
                trailingActionsContent
                    .padding(pillInsets)
                    .contentShape(Capsule())
                    .glassEffect(.clear, in: .capsule)
            }
            .transaction { $0.animation = nil }
        } else {
            groupedTrailingFallback
        }
        #else
        groupedTrailingFallback
        #endif
    }

    private var groupedTrailingFallback: some View {
        trailingActionsContent
            .padding(pillInsets)
            .thinMaterialBackgroundCompat(in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
            .contentShape(Capsule())
    }

    @ViewBuilder
    private var ungroupedTrailingIconActions: some View {
        if showsPiP {
            PiPButton(playerManager: playerManager)
        }
        if !showsPiP && showsRotate {
            RotateButtonView(playerManager: playerManager)
        }
        if !showsPiP && !showsRotate && showsFullscreen {
            FullscreenButtonView(playerManager: playerManager)
        }
    }
}

@MainActor
private struct LiveStatusView: View {
    @ObservedObject var playerManager: PlayerManager

    @ViewBuilder
    var body: some View {
        if let isAtLiveEdge = playerManager.isAtLiveEdge {
            if isAtLiveEdge {
                label(playerManager.strings.live)
                    .accessibilityLabel(playerManager.strings.live)
            } else {
                Button(action: playerManager.goLive) {
                    label(playerManager.strings.goLive)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(playerManager.strings.goLive)
                .accessibilityHint(playerManager.strings.goLiveHint)
            }
        }
    }

    private func label(_ title: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color.black.opacity(0.45))
        .clipShape(Capsule())
        .contentShape(Capsule())
    }
}
