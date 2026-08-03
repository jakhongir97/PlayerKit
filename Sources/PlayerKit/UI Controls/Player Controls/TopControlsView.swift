import SwiftUI

@MainActor
struct TopControlsView: View {
    @Environment(\.sizeCategory) private var sizeCategory
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        HStack(spacing: 8) {
            CloseButtonView(playerManager: playerManager)
            VStack(alignment: .leading, spacing: 2) {
                if let item = playerManager.playerItem {
                    PlayerTitleView(title: item.title, imageURL: item.titleImageURL)

                    if let description = item.description {
                        Text(description)
                            .font(.callout.weight(.medium))
                            .foregroundColor(.white)
                            .lineLimit(sizeCategory.isAccessibilityCategory ? 2 : 1)
                    }
                }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            SharingMenuView(
                playerManager: playerManager,
                isAirPlayEnabled: playerManager.canUseAirPlay
            )
            SettingsMenu(playerManager: playerManager)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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

    /// Sized against the 25pt text title it stands in for: tall enough to read
    /// a title treatment, short enough that a wide one cannot push the
    /// controls to its right off the bar.
    private static let maxImageWidth: CGFloat = 280
    private static let maxImageHeight: CGFloat = 44

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
            .font(.title2.weight(.semibold))
            .foregroundColor(.white)
            .lineLimit(sizeCategory.isAccessibilityCategory ? 2 : 1)
    }
}
