import Foundation

/// High-level facade for integrating PlayerKit with minimal setup.
@MainActor
public final class Player {
    public let playerManager: PlayerManager

    public init(playerManager: PlayerManager = .shared, preferredType: PlayerType? = nil) {
        self.playerManager = playerManager
        playerManager.ensurePlayerConfigured(type: preferredType)
    }

    public func configure(playerType: PlayerType) {
        playerManager.ensurePlayerConfigured(type: playerType)
    }

    public func load(
        url: URL,
        title: String? = nil,
        titleImageURL: URL? = nil,
        description: String? = nil,
        posterURL: URL? = nil,
        thumbnailVTTURL: URL? = nil,
        castVideoURL: URL? = nil,
        externalPlaybackURL: URL? = nil,
        externalPlaybackContentType: String? = nil,
        externalPlaybackDuration: Double? = nil,
        lastPosition: Double? = nil
    ) {
        playerManager.ensurePlayerConfigured()

        let item = PlayerItem(
            title: title ?? inferredTitle(from: url),
            titleImageURL: titleImageURL,
            description: description,
            url: url,
            posterUrl: posterURL,
            thumbnailVTTURL: thumbnailVTTURL,
            castVideoUrl: castVideoURL,
            externalPlaybackURL: externalPlaybackURL,
            externalPlaybackContentType: externalPlaybackContentType,
            externalPlaybackDuration: externalPlaybackDuration,
            lastPosition: lastPosition
        )
        playerManager.load(playerItem: item)
    }

    public func load(
        playerItem: PlayerItem,
        preservingTrackSelection: Bool = false
    ) {
        playerManager.ensurePlayerConfigured()
        playerManager.load(
            playerItem: playerItem,
            preservingTrackSelection: preservingTrackSelection
        )
    }

    public func load(playerItems: [PlayerItem], currentIndex: Int = 0) {
        playerManager.ensurePlayerConfigured()
        playerManager.loadEpisodes(playerItems: playerItems, currentIndex: currentIndex)
    }

    public func play() {
        playerManager.ensurePlayerConfigured()
        playerManager.play()
    }

    public func pause() {
        playerManager.pause()
    }

    public func stop() {
        playerManager.stop()
    }

    public func seek(to time: Double) {
        playerManager.seek(to: time)
    }

    public func makeView() -> PlayerView {
        PlayerView(playerManager: playerManager)
    }

    private func inferredTitle(from url: URL) -> String {
        let fallback = playerManager.strings.defaultStreamTitle
        let lastPath = url.lastPathComponent
        guard !lastPath.isEmpty else { return fallback }

        let trimmed = lastPath
            .removingPercentEncoding?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return fallback
    }
}
