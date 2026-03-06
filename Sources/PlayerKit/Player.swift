import Foundation

/// High-level facade for integrating PlayerKit with minimal setup.
public final class Player {
    public let playerManager: PlayerManager

    public init(playerManager: PlayerManager = .shared, preferredType: PlayerType? = nil) {
        self.playerManager = playerManager
        playerManager.ensurePlayerConfigured(type: preferredType)
    }

    public func configure(playerType: PlayerType) {
        playerManager.ensurePlayerConfigured(type: playerType)
    }

    @MainActor
    public func configureDubber(_ configuration: DubberConfiguration?) {
        playerManager.configureDubber(configuration)
    }

    @MainActor
    public func startDubbedPlayback(language: String? = nil, translateFrom: String? = nil) async {
        await playerManager.startDubbedPlayback(language: language, translateFrom: translateFrom)
    }

    @MainActor
    public func setDubLanguage(code: String) {
        playerManager.setDubLanguage(code: code)
    }

    @MainActor
    public func setDubSourceLanguage(code: String) {
        playerManager.setDubSourceLanguage(code: code)
    }

    @MainActor
    public func stopDubbingAndReturnToOriginalAudio() {
        playerManager.stopDubbingAndReturnToOriginalAudio()
    }

    public func load(
        url: URL,
        title: String? = nil,
        description: String? = nil,
        posterURL: URL? = nil,
        castVideoURL: URL? = nil,
        lastPosition: Double? = nil
    ) {
        playerManager.ensurePlayerConfigured()

        let item = PlayerItem(
            title: title ?? inferredTitle(from: url),
            description: description,
            url: url,
            posterUrl: posterURL,
            castVideoUrl: castVideoURL,
            lastPosition: lastPosition
        )
        playerManager.load(playerItem: item)
    }

    public func load(playerItem: PlayerItem) {
        playerManager.ensurePlayerConfigured()
        playerManager.load(playerItem: playerItem)
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
        let fallback = "PlayerKit Stream"
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
