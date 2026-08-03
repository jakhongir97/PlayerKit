import XCTest
@testable import PlayerKit

final class PlayerStringsTests: XCTestCase {
    func testEnglishDefaultsPreserveExistingDynamicCopy() {
        let strings = PlayerStrings()

        XCTAssertEqual(strings.play, "Play")
        XCTAssertEqual(strings.playbackPositionValue("01:02", "42:00"), "01:02 of 42:00")
        XCTAssertEqual(strings.skipForwardSeconds(10), "Skip forward 10 seconds")
        XCTAssertEqual(strings.forwardSeconds(12.5), "Forward 12.5 seconds")
        XCTAssertEqual(strings.playbackSpeedOption(1, true), "1.0x (Normal)")
        XCTAssertEqual(strings.playbackQualityTitle, "Quality")
        XCTAssertEqual(strings.optimalQuality, "Optimal")
        XCTAssertEqual(strings.gestureSpeedValue(2), "2×")
    }

    func testHostFormattersOwnWordOrderAndGrammar() {
        var strings = PlayerStrings()
        strings.forwardSeconds = { "Вперёд на \(Int($0)) секунд" }
        strings.volumeAnnouncement = { "Громкость: \($0)" }
        strings.scrubAnnouncement = { position, detail in
            "Позиция \(position)\(detail.map { ", \($0)" } ?? "")"
        }

        XCTAssertEqual(strings.forwardSeconds(30), "Вперёд на 30 секунд")
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

    func testInjectedErrorCopyNeverUsesBackendDetail() {
        let secret = "https://cdn.example/video.m3u8?token=secret"
        var strings = PlayerStrings()
        strings.playbackUnavailableTitle = "Видео недоступно"
        strings.playbackUnavailableMessage = "Повторите попытку."
        strings.mediaLoadFailedDescription = "Не удалось загрузить видео."

        let presentation = PlaybackErrorPresentation(
            .mediaLoadFailed(secret),
            strings: strings
        )
        XCTAssertEqual(presentation.title, "Видео недоступно")
        XCTAssertEqual(presentation.message, "Повторите попытку.")
        XCTAssertEqual(
            PlayerKitError.mediaLoadFailed(secret).userFacingDescription(using: strings),
            "Не удалось загрузить видео."
        )
        XCTAssertFalse(presentation.message.contains(secret))
    }
}
