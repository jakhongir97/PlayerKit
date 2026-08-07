import SwiftUI

@MainActor
struct TopControlsView: View {
    @Environment(\.sizeCategory) private var sizeCategory
    @ObservedObject var playerManager: PlayerManager

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

    /// Close on the left, identity in the middle, session actions grouped on
    /// the right.
    ///
    /// The info button used to float alone against the *left* edge at the
    /// player's vertical midpoint, and the lock against the right one, with
    /// nothing between them but video — two orphans on a line of their own. Both
    /// are session-level actions, so both live with the rest of them.
    var body: some View {
        HStack(alignment: .top, spacing: PlayerChromeMetrics.spacingM) {
            CloseButtonView(playerManager: playerManager)
                .chromeGated(showsChrome)

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
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            // Centres the text block against the close button's disc rather
            // than hanging it from the very top of the bar.
            .frame(minHeight: PlayerChromeMetrics.minimumHitTarget, alignment: .center)
            .chromeGated(showsChrome)

            trailingActions
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// The lock is gated on `areControlsVisible` alone, not on `showsChrome`.
    ///
    /// It is the only way out of a locked player, so it has to outlive the
    /// chrome it belongs to. Keeping it in this row rather than floating it
    /// somewhere safe means it does not move when the lock engages — the rest
    /// of the row goes invisible around it while still occupying its space, so
    /// the button the user reaches for is exactly where it was.
    private var trailingActions: some View {
        HStack(spacing: PlayerChromeMetrics.spacingS) {
            SharingMenuView(
                playerManager: playerManager,
                isAirPlayEnabled: playerManager.canUseAirPlay
            )
            .chromeGated(showsChrome)

            InfoButtonView(playerManager: playerManager)
                .chromeGated(showsChrome)

            SettingsMenu(playerManager: playerManager)
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
