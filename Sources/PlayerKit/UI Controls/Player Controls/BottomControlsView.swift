import SwiftUI

@MainActor
struct BottomControlsView: View {
    @ObservedObject var playerManager: PlayerManager

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
            MediaOptionsMenu(playerManager: playerManager)
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
            HStack(spacing: 12) {
                MediaOptionsMenu(playerManager: playerManager)
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
