import XCTest
@testable import PlayerKit

final class PlayerStringsTests: XCTestCase {
    func testEnglishDefaultsPreserveExistingDynamicCopy() {
        let strings = PlayerStrings()

        XCTAssertEqual(strings.play, "Play")
        XCTAssertEqual(strings.playbackPositionValue("01:02", "42:00"), "01:02 of 42:00")
        XCTAssertEqual(strings.skipIntervalValue(1.25), "1.25")
        XCTAssertEqual(strings.skipForwardSeconds(10), "Skip forward 10 seconds")
        XCTAssertEqual(strings.forwardSeconds(12.5), "Forward 12.5 seconds")
        XCTAssertEqual(strings.playbackSpeedOption(1, true), "1.0x (Normal)")
        XCTAssertEqual(strings.playbackQualityTitle, "Quality")
        XCTAssertEqual(strings.optimalQuality, "Optimal")
        XCTAssertEqual(strings.gestureSpeedValue(2), "2×")
        XCTAssertEqual(strings.streamingBufferDurationValue(12.5), "12.5 sec")
        XCTAssertEqual(strings.streamingVideoBitrateValue(1.25), "1.25 Mbps")
        XCTAssertEqual(strings.streamingFrameRateValue(23.976), "23.98 fps")
        XCTAssertEqual(strings.streamingResolutionValue(1920, 1080), "1920x1080")
    }

    func testHostFormattersOwnWordOrderAndGrammar() {
        var strings = PlayerStrings()
        strings.forwardSeconds = { "Вперёд на \(Int($0)) секунд" }
        strings.skipIntervalValue = { _ in "1,25" }
        strings.volumeAnnouncement = { "Громкость: \($0)" }
        strings.scrubAnnouncement = { position, detail in
            "Позиция \(position)\(detail.map { ", \($0)" } ?? "")"
        }

        XCTAssertEqual(strings.forwardSeconds(30), "Вперёд на 30 секунд")
        XCTAssertEqual(strings.skipIntervalValue(1.25), "1,25")
        XCTAssertEqual(strings.volumeAnnouncement("62%"), "Громкость: 62%")

        let hud = GestureHUD(
            kind: .scrub,
            slot: .banner,
            symbol: "forward.fill",
            primary: "12:04",
            secondary: "+0:30",
            tertiary: nil,
            fraction: nil
        )
        XCTAssertEqual(
            hud.accessibilityAnnouncement(using: strings),
            "Позиция 12:04, +0:30"
        )
    }

    func testStreamingInfoAndDebugCopyUseInjectedStrings() {
        var strings = PlayerStrings()
        strings.streamingUnknownValue = "Noma’lum"
        strings.streamingBufferDurationValue = { "\(Int($0)) soniya" }
        strings.streamingVideoBitrateValue = { "\($0) Mbit/s" }
        strings.streamingFrameRateValue = { "\($0) kadr/s" }
        strings.streamingResolutionValue = { "\($0)×\($1)" }
        strings.vlcPlaybackEngineName = "VLC dvigateli"
        strings.avPlaybackEngineName = "AV dvigateli"

        let placeholder = StreamingInfo.placeholder(using: strings)
        XCTAssertEqual(placeholder.frameRate, "Noma’lum")
        XCTAssertEqual(placeholder.videoBitrate, "0.0 Mbit/s")
        XCTAssertEqual(placeholder.resolution, "Noma’lum")
        XCTAssertEqual(placeholder.bufferDuration, "0 soniya")
        XCTAssertEqual(PlayerType.vlcPlayer.title(using: strings), "VLC dvigateli")
        XCTAssertEqual(PlayerType.avPlayer.title(using: strings), "AV dvigateli")
    }

    @MainActor
    func testLegacyStreamingInfoConformerKeepsSourceCompatibleDefault() {
        let probe = LegacyStreamingInfoProbe()
        var strings = PlayerStrings()
        strings.streamingUnknownValue = "Unused"

        XCTAssertEqual(probe.fetchStreamingInfo(using: strings).frameRate, "Legacy")
    }

    @MainActor
    func testStreamingInfoViewStartsWithInjectedPlaceholder() {
        let manager = PlayerManager.shared
        let original = manager.strings
        defer { manager.strings = original }

        var strings = original
        strings.streamingUnknownValue = "Noma’lum"
        strings.streamingVideoBitrateValue = { "\($0) Mbit/s" }
        strings.streamingBufferDurationValue = { "\(Int($0)) soniya" }
        manager.strings = strings

        let view = StreamingInfoView(playerManager: manager)
        XCTAssertEqual(view.streamingInfo.frameRate, "Noma’lum")
        XCTAssertEqual(view.streamingInfo.videoBitrate, "0.0 Mbit/s")
        XCTAssertEqual(view.streamingInfo.bufferDuration, "0 soniya")
    }

    @MainActor
    func testLegacySkipTitlesAndPlayerStringsShareOneStoredValue() {
        let manager = PlayerManager.shared
        let original = manager.strings
        defer { manager.strings = original }

        manager.heuristicSkipButtonTitles = HeuristicSkipButtonTitles(
            skipIntro: "Пропустить заставку",
            skipOutro: "Пропустить титры",
            nextEpisode: "Следующая серия"
        )
        XCTAssertEqual(manager.strings.heuristicSkipButtonTitles.skipIntro, "Пропустить заставку")

        var copy = manager.strings
        copy.heuristicSkipButtonTitles.nextEpisode = "Keyingi qism"
        copy.locked = "Qulflangan"
        manager.strings = copy

        XCTAssertEqual(manager.heuristicSkipButtonTitles.nextEpisode, "Keyingi qism")
        XCTAssertEqual(manager.gestureManager.strings.locked, "Qulflangan")
    }

    func testInjectedErrorCopyAndLocalizedDescriptionNeverUseBackendDetail() {
        let secret = "https://cdn.example/video.m3u8?token=secret"
        var strings = PlayerStrings()
        strings.playbackUnavailableTitle = "Видео недоступно"
        strings.playbackUnavailableMessage = "Повторите попытку."
        strings.mediaLoadFailedDescription = "Не удалось загрузить видео."

        let errors: [PlayerKitError] = [
            .mediaLoadFailed(secret),
            .pictureInPictureFailed(secret),
            .castSessionUnavailable,
            .castURLMissing,
            .externalPlaybackDeviceUnavailable,
            .externalPlaybackURLMissing,
            .externalPlaybackRequiresReachableURL,
            .externalPlaybackFailed(secret),
            .unknown(secret)
        ]
        let presentation = PlaybackErrorPresentation(.mediaLoadFailed(secret), strings: strings)
        XCTAssertEqual(presentation.title, "Видео недоступно")
        XCTAssertEqual(presentation.message, "Повторите попытку.")
        XCTAssertEqual(
            PlayerKitError.mediaLoadFailed(secret).userFacingDescription(using: strings),
            "Не удалось загрузить видео."
        )
        for error in errors {
            XCTAssertFalse(error.localizedDescription.contains(secret))
            XCTAssertFalse(error.userFacingDescription(using: strings).contains(secret))
        }
        XCTAssertFalse(presentation.message.contains(secret))
    }
}

@MainActor
private final class LegacyStreamingInfoProbe: StreamingInfoProtocol {
    func fetchStreamingInfo() -> StreamingInfo {
        StreamingInfo(
            frameRate: "Legacy",
            videoBitrate: "Legacy",
            resolution: "Legacy",
            bufferDuration: "Legacy"
        )
    }
}
