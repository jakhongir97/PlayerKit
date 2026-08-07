import SwiftUI

@MainActor
struct BottomControlsView: View {
    @ObservedObject var playerManager: PlayerManager
    let presentationPolicy: PlayerPresentationPolicy
    let availableWidth: CGFloat

    /// Below this the bar cannot hold a leading and a trailing cluster on one
    /// line, and stacks into two rows instead.
    ///
    /// Derived from what the row actually contains at its widest: a live pill
    /// (~96), the four-icon options pill (~4 × 38 + insets ≈ 180), the skip
    /// pill (~150) and three trailing icons (~130), plus the gaps between
    /// them. Anything narrower than this and the `Spacer` between the clusters
    /// goes to zero and the pills collide.
    static let singleRowMinimumWidth: CGFloat = 560

    init(
        playerManager: PlayerManager,
        presentationPolicy: PlayerPresentationPolicy,
        availableWidth: CGFloat = .greatestFiniteMagnitude
    ) {
        self.playerManager = playerManager
        self.presentationPolicy = presentationPolicy
        self.availableWidth = availableWidth
    }

    private var isIPhone: Bool { PlayerKitPlatform.isPhone }
    private var appearance: PlayerAppearance { playerManager.appearance }
    private var showsPiP: Bool { playerManager.isPiPSupported }
    private var showsRotate: Bool { isIPhone }
    private var showsFullscreen: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }
    private var trailingIconCount: Int {
        [showsPiP, showsRotate, showsFullscreen].filter { $0 }.count
    }
    private var showsTrailingIconActions: Bool { trailingIconCount > 0 }

    static func usesSingleRow(availableWidth: CGFloat) -> Bool {
        availableWidth >= singleRowMinimumWidth
    }

    private var usesSingleRow: Bool {
        Self.usesSingleRow(availableWidth: availableWidth)
    }

    /// One bar, laid out edge to edge.
    ///
    /// This used to be a `ViewThatFits` whose first candidate carried
    /// `.fixedSize(horizontal: true, vertical: false)`. `fixedSize` was there
    /// to stop the flexible row from reporting that it fits at any width, but
    /// it also applies to the row that gets *chosen*: the bar was then laid out
    /// at its content width and centred, so its `Spacer` collapsed and every
    /// control bunched into the middle of the player with empty space on both
    /// sides. On a 1120pt window the bar occupied 316pt of a 1056pt band. The
    /// breakpoint is now an explicit width comparison, which both spans
    /// properly and can be asserted in a test.
    var body: some View {
        Group {
            if usesSingleRow {
                singleRow
            } else {
                stackedRows
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var singleRow: some View {
        HStack(spacing: PlayerChromeMetrics.spacingM) {
            leadingCluster
            Spacer(minLength: PlayerChromeMetrics.spacingL)
            trailingCluster
        }
    }

    /// Narrow surfaces give the live badge its own line.
    ///
    /// On an iPhone in portrait the three clusters do not fit together: a live
    /// pill, a four-glyph options pill and a two-icon trailing group already
    /// exceed the content width, and every one of them is a fixed-height pill
    /// with a content-derived width, so the row has nothing to compress but the
    /// badge's text.
    private var stackedRows: some View {
        VStack(alignment: .leading, spacing: PlayerChromeMetrics.spacingS) {
            if showsCompactLiveStatusRow {
                HStack(spacing: 0) {
                    LiveStatusView(playerManager: playerManager)
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: PlayerChromeMetrics.spacingM) {
                MediaOptionsMenu(
                    playerManager: playerManager,
                    presentationPolicy: presentationPolicy
                )
                Spacer(minLength: PlayerChromeMetrics.spacingS)
                trailingIconActions
            }

            // No `if` around this row: the skip buttons render `EmptyView`
            // outside their marker windows, and a VStack child that is empty
            // contributes no spacing — whereas a row reserved on the timeline
            // mode alone is present for the whole of a VOD session and leaves
            // 8pt of dead space under the bar for all of it.
            HStack(spacing: PlayerChromeMetrics.spacingS) {
                Spacer(minLength: 0)
                skipActions
            }
        }
    }

    @ViewBuilder
    private var leadingCluster: some View {
        HStack(spacing: PlayerChromeMetrics.spacingM) {
            LiveStatusView(playerManager: playerManager)
            MediaOptionsMenu(
                playerManager: playerManager,
                presentationPolicy: presentationPolicy
            )
        }
    }

    /// Skip sits at the trailing edge, next to the other things that move you
    /// forward, rather than wedged between the live badge and the options pill
    /// where it was competing with settings controls for the eye.
    @ViewBuilder
    private var trailingCluster: some View {
        HStack(spacing: PlayerChromeMetrics.spacingM) {
            if usesSingleRow {
                skipActions
            }
            trailingIconActions
        }
    }

    @ViewBuilder
    private var skipActions: some View {
        SkipIntroButtonView(playerManager: playerManager)
        SkipOutroButtonView(playerManager: playerManager)
    }

    /// Grouped icons supply one shared surface and their glyphs supply none.
    ///
    /// They used to be `circularGlassIcon` buttons — each with its own glass
    /// disc and hairline — placed *inside* a glass capsule, so the row showed
    /// stroked discs floating in a stroked pill: glass stacked on glass, which
    /// reads as a smudge rather than as a material. A single icon keeps its own
    /// disc, because then there is no group for it to sit in.
    @ViewBuilder
    private var trailingIconActions: some View {
        if showsTrailingIconActions {
            if trailingIconCount > 1 {
                PlayerGlassGroup {
                    HStack(spacing: PlayerChromeMetrics.spacingXS) {
                        trailingActionGlyphs(grouped: true)
                    }
                    .padding(.horizontal, PlayerChromeMetrics.spacingS)
                    // `minHeight`, not a fixed height: the glyphs inside carry
                    // their own 44pt minimum target, and a hard 44 here would
                    // clip them back out of it.
                    .frame(minHeight: PlayerChromeMetrics.barItemHeight)
                    .playerSurfaceShape(.capsule)
                    .playerGlass(.capsule, prominence: .bar, appearance: appearance)
                }
            } else {
                trailingActionGlyphs(grouped: false)
            }
        }
    }

    @ViewBuilder
    private func trailingActionGlyphs(grouped: Bool) -> some View {
        if showsPiP {
            PiPButton(playerManager: playerManager, isGrouped: grouped)
        }
        if showsRotate {
            RotateButtonView(playerManager: playerManager, isGrouped: grouped)
        }
        if showsFullscreen {
            FullscreenButtonView(playerManager: playerManager, isGrouped: grouped)
        }
    }

    var showsCompactLiveStatusRow: Bool {
        playerManager.isAtLiveEdge != nil
    }
}

@MainActor
private struct LiveStatusView: View {
    @ObservedObject var playerManager: PlayerManager

    @ViewBuilder
    var body: some View {
        if let isAtLiveEdge = playerManager.isAtLiveEdge {
            if isAtLiveEdge {
                label(playerManager.strings.live, isInteractive: false)
                    .accessibilityLabel(playerManager.strings.live)
            } else {
                Button(action: playerManager.goLive) {
                    label(playerManager.strings.goLive, isInteractive: true)
                }
                .buttonStyle(PlayerControlButtonStyle())
                .accessibilityLabel(playerManager.strings.goLive)
                .accessibilityHint(playerManager.strings.goLiveHint)
            }
        }
    }

    /// The live badge is on the shared bar surface, not on the flat
    /// `black.opacity(0.45)` capsule it used to carry — that was a third black
    /// value in a row that already had two, and the only capsule in the chrome
    /// without a hairline.
    private func label(_ title: String, isInteractive: Bool) -> some View {
        HStack(spacing: PlayerChromeMetrics.spacingS) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(title)
                .playerChromeFont(.badge)
                .trackingCompat(0.6)
                .foregroundColor(.white)
        }
        .padding(.horizontal, PlayerChromeMetrics.pillHorizontalPadding)
        .frame(height: PlayerChromeMetrics.barItemHeight)
        .playerSurfaceShape(.capsule)
        .playerGlass(.capsule, prominence: .bar, appearance: playerManager.appearance)
    }
}
