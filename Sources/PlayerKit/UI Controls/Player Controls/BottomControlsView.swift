import SwiftUI

struct BottomControlsView: View {
    @ObservedObject var playerManager: PlayerManager

    private var isIPhone: Bool { PlayerKitPlatform.isPhone }
    private let pillInsets = EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
    private var showsPiP: Bool { playerManager.isPiPSupported }
    private var showsRotate: Bool { isIPhone }
    private var showsTrailingIconActions: Bool {
        showsPiP || showsRotate
    }
    private var shouldGroupTrailingIconActions: Bool {
        [showsPiP, showsRotate].filter { $0 }.count > 1
    }

    var body: some View {
        HStack(spacing: 12) {
            MediaOptionsMenu(playerManager: playerManager)
            BufferingIndicatorView(playerManager: playerManager)
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

    @ViewBuilder
    private var trailingActionsContent: some View {
        HStack {
            if showsPiP {
                PiPButton(playerManager: playerManager)
            }
            if showsRotate {
                RotateButtonView(playerManager: playerManager)
            }
        }
    }

    @ViewBuilder
    private var groupedTrailingIconActions: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer {
                trailingActionsContent
                    .padding(pillInsets)
                    .contentShape(Capsule())
                    .glassEffect(.clear, in: .capsule)
            }
            .transaction { $0.animation = nil }
        } else if #available(iOS 15.0, macOS 12.0, *) {
            trailingActionsContent
                .padding(pillInsets)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                .contentShape(Capsule())
        } else {
            trailingActionsContent
                .padding(pillInsets)
                .background(Color.white.opacity(0.10))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .contentShape(Capsule())
        }
    }

    @ViewBuilder
    private var ungroupedTrailingIconActions: some View {
        if showsPiP {
            PiPButton(playerManager: playerManager)
        }
        if !showsPiP && showsRotate {
            RotateButtonView(playerManager: playerManager)
        }
    }
}
