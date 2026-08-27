import SwiftUI

@MainActor
struct TopControlsView: View {
    @Environment(\.sizeCategory) private var sizeCategory
    @ObservedObject var playerManager: PlayerManager
    /// The content width the bar is laid out in; see ``Arrangement``.
    let availableWidth: CGFloat

    init(playerManager: PlayerManager, availableWidth: CGFloat = .greatestFiniteMagnitude) {
        self.playerManager = playerManager
        self.availableWidth = availableWidth
    }

    enum Arrangement: Equatable {
        /// Close, identity and the action cluster share one line.
        case inline
        /// Close and the action cluster share the first line; the identity
        /// gets the whole of a second.
        case stacked
    }

    /// The narrowest a title can be and still be read as one.
    ///
    /// Below this the inline bar was handing the title ~50pt on an iPhone in
    /// portrait — five trailing discs plus the close disc leave that much of a
    /// 370pt content width — and "Веном" rendered as "Вен…". A title that is
    /// all ellipsis is not a title, so the bar gives it a line of its own.
    static let minimumInlineTitleWidth: CGFloat = 160

    /// The width `count` trailing controls occupy: every disc sits inside the
    /// 44pt minimum target, with `spacing` between neighbours.
    static func trailingClusterWidth(
        controlCount count: Int,
        spacing: CGFloat = PlayerChromeMetrics.spacingS
    ) -> CGFloat {
        guard count > 0 else { return 0 }
        return (PlayerChromeMetrics.minimumHitTarget * CGFloat(count))
            + (spacing * CGFloat(count - 1))
    }

    /// The gap between trailing discs, tightened before the row can overflow.
    ///
    /// A release build's five discs need 252pt at the ordinary 8pt gap, and a
    /// 320pt iPhone in portrait leaves the cluster 238pt once the close disc
    /// has its own, so the lock was pushed flush with — or past — the trailing
    /// edge. At 4pt the same five fit in 236pt. The discs themselves never
    /// shrink: they are already at the minimum touch target.
    ///
    /// A hypothetical five-disc cluster fits a 320pt surface only at the
    /// tighter gap. The shipping bar keeps occasional actions inside More,
    /// but this geometry still protects future top-level controls.
    static func clusterSpacing(availableWidth: CGFloat, trailingControlCount count: Int) -> CGFloat {
        let budget = availableWidth
            - PlayerChromeMetrics.minimumHitTarget   // close
            - PlayerChromeMetrics.spacingM           // close → cluster
        let relaxed = trailingClusterWidth(controlCount: count, spacing: PlayerChromeMetrics.spacingS)
        return relaxed <= budget ? PlayerChromeMetrics.spacingS : PlayerChromeMetrics.spacingXS
    }

    /// The width left for the identity block when everything shares a line.
    static func inlineTitleWidth(availableWidth: CGFloat, trailingControlCount: Int) -> CGFloat {
        availableWidth
            - PlayerChromeMetrics.minimumHitTarget          // close
            - PlayerChromeMetrics.spacingM                  // close → title
            - PlayerChromeMetrics.spacingM                  // title → cluster
            - trailingClusterWidth(
                controlCount: trailingControlCount,
                spacing: clusterSpacing(
                    availableWidth: availableWidth,
                    trailingControlCount: trailingControlCount
                )
            )
    }

    static func arrangement(availableWidth: CGFloat, trailingControlCount: Int) -> Arrangement {
        inlineTitleWidth(availableWidth: availableWidth, trailingControlCount: trailingControlCount)
            >= minimumInlineTitleWidth
            ? .inline
            : .stacked
    }

    static func showsPlayerSwitcher(supportedPlayerCount: Int) -> Bool {
        supportedPlayerCount > 1
    }

    /// Whether the row's ordinary contents are showing. The lock ignores this —
    /// see ``trailingActions``.
    var showsChrome: Bool {
        playerManager.areControlsVisible && !playerManager.isLocked
    }

    /// Whether the unlock affordance is showing. Deliberately independent of
    /// ``showsChrome``: a locked player whose only way out is hidden is a trap.
    var showsUnlockControl: Bool {
        playerManager.areControlsVisible
    }

    /// The host's rows are offered inside the options panel; the panel itself
    /// is always present, because playback information always is.
    var showsHostActions: Bool {
        !playerManager.hostActions.presentable.isEmpty
    }

    /// Product invariant: route and backend actions live inside More at every
    /// width. The only top-level trailing controls are More and lock.
    var trailingControlCount: Int { 2 }

    var arrangement: Arrangement {
        Self.arrangement(availableWidth: availableWidth, trailingControlCount: trailingControlCount)
    }

    /// Close on the left, identity in the middle, session actions grouped on
    /// the right — or, where the middle would be squeezed to nothing, the
    /// identity on a line of its own under the close disc.
    ///
    /// The info button used to float alone against the *left* edge at the
    /// player's vertical midpoint, and the lock against the right one, with
    /// nothing between them but video — two orphans on a line of their own. Both
    /// are session-level actions, so both live with the rest of them.
    var body: some View {
        // One tree for both arrangements. The close disc and the trailing
        // cluster keep their structural identity when the bar re-lays out on
        // rotation, so an open info popover or menu survives the switch; only
        // the identity block moves between the first line and its own.
        VStack(alignment: .leading, spacing: PlayerChromeMetrics.spacingS) {
            HStack(alignment: .top, spacing: PlayerChromeMetrics.spacingM) {
                CloseButtonView(playerManager: playerManager)
                    .chromeGated(showsChrome)

                if arrangement == .inline {
                    identity
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                        // Centres the text block against the close button's
                        // disc rather than hanging it from the very top of the
                        // bar.
                        .frame(minHeight: PlayerChromeMetrics.minimumHitTarget, alignment: .center)
                        .chromeGated(showsChrome)
                } else {
                    Spacer(minLength: 0)
                }

                trailingActions
            }

            if arrangement == .stacked {
                identity
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .chromeGated(showsChrome)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let item = playerManager.playerItem {
                PlayerTitleView(title: item.title, imageURL: item.titleImageURL)

                if let description = item.description, description != item.title {
                    Text(description)
                        .playerChromeFont(.subtitle)
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(sizeCategory.isAccessibilityCategory ? 2 : 1)
                }
            }
        }
    }

    /// The lock is gated on `areControlsVisible` alone, not on `showsChrome`.
    ///
    /// It is the only way out of a locked player, so it has to outlive the
    /// chrome it belongs to. Keeping it in this row rather than floating it
    /// somewhere safe means it does not move when the lock engages — the rest
    /// of the row goes invisible around it while still occupying its space, so
    /// the button the user reaches for is exactly where it was.
    private var trailingActions: some View {
        HStack(spacing: Self.clusterSpacing(
            availableWidth: availableWidth,
            trailingControlCount: trailingControlCount
        )) {
            PlayerOptionsMenuView(playerManager: playerManager)
                .chromeGated(showsChrome)

            LockButtonView(playerManager: playerManager)
                .chromeGated(showsUnlockControl)
        }
    }
}

private extension View {
    /// Hides a control completely: invisible, untappable, and absent from
    /// accessibility — but still occupying its slot, so its neighbours do not
    /// reflow when it goes.
    @ViewBuilder
    func chromeGated(_ isPresented: Bool) -> some View {
        opacity(isPresented ? 1 : 0)
            .allowsHitTesting(isPresented)
            .accessibilityHidden(!isPresented)
    }
}

/// The item's title treatment when the host supplies one, its text title
/// otherwise.
///
/// PlayerKit fetches this URL even though it refuses to fetch
/// `PlayerItem.posterUrl` (see `PlayerManager.nowPlayingArtwork`). The
/// objection there is about owning an image cache: the lock screen needs a
/// decoded image up front and has nothing to show while one is fetched. A
/// view is not in that position — it renders the text title until the image
/// arrives, and keeps rendering it if the fetch fails — so no cache or
/// network policy has to move into PlayerKit for this to degrade well.
private struct PlayerTitleView: View {
    @Environment(\.sizeCategory) private var sizeCategory
    let title: String
    let imageURL: URL?

    /// Sized against the text title it stands in for: tall enough to read a
    /// title treatment, short enough that a wide one cannot push the controls
    /// to its right off the bar.
    private static let maxImageWidth: CGFloat = 280
    private static let maxImageHeight: CGFloat = 40

    var body: some View {
        if let imageURL {
            if #available(iOS 15.0, macOS 12.0, *) {
                AsyncImage(
                    url: imageURL,
                    // Crossfade, so a cold fetch resolving into the artwork does
                    // not read as a glitch.
                    transaction: Transaction(animation: .easeInOut(duration: 0.2))
                ) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(
                                maxWidth: Self.maxImageWidth,
                                maxHeight: Self.maxImageHeight,
                                alignment: .leading
                            )
                            .accessibilityLabel(Text(title))
                    default:
                        // Only the artwork is boxed: the fallback keeps the width
                        // the text title has always had.
                        titleText
                    }
                }
            } else {
                // ponytail: iOS 14 keeps the reliable text title; native async
                // image loading begins on iOS 15 without adding a loader/cache.
                titleText
            }
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(title)
            .playerChromeFont(.title)
            .foregroundColor(.white)
            .lineLimit(sizeCategory.isAccessibilityCategory ? 2 : 1)
    }
}
