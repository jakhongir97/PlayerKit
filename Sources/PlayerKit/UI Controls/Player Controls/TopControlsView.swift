import SwiftUI

struct TopControlsView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        HStack {
            CloseButtonView(playerManager: playerManager)
            VStack(alignment: .leading) {
                if let item = playerManager.playerItem {
                    PlayerTitleView(title: item.title, imageURL: item.titleImageURL)

                    if let description = item.description {
                        Text(description)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal)
            Spacer()

            SharingMenuView(isAirPlayEnabled: playerManager.isExternalPlaybackEnabled)
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
    let title: String
    let imageURL: URL?

    /// Sized against the 25pt text title it stands in for: tall enough to read
    /// a title treatment, short enough that a wide one cannot push the
    /// controls to its right off the bar.
    private static let maxImageWidth: CGFloat = 280
    private static let maxImageHeight: CGFloat = 44

    var body: some View {
        if let imageURL {
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
            titleText
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.system(size: 25, weight: .semibold))
            .foregroundColor(.white)
            .lineLimit(1)
    }
}
