import Combine
import CoreGraphics
import XCTest
@testable import PlayerKit

#if os(macOS)
import AppKit
#endif

@MainActor
final class PlatformInteractionRegressionTests: XCTestCase {
    func testPlaybackToggleUsesDurableRequestedStateForActionAndHUD() {
        let manager = GestureManager(clock: TestClock())
        var requested = false
        manager.isPlayingProvider = { true }
        manager.isPlaybackRequestedProvider = { requested }
        manager.onTogglePlayback = { requested.toggle() }

        manager.twoFingerTap()
        flushGestureHUD()

        XCTAssertTrue(requested)
        XCTAssertEqual(manager.hudModel.hud?.primary, "Play")
        XCTAssertEqual(manager.hudModel.hud?.symbol, "play.fill")

        manager.isPlayingProvider = { false }
        manager.twoFingerTap()
        flushGestureHUD()

        XCTAssertFalse(requested)
        XCTAssertEqual(manager.hudModel.hud?.primary, "Pause")
        XCTAssertEqual(manager.hudModel.hud?.symbol, "pause.fill")
    }

    func testUnavailableZoomDoesNotChangeStateOrConfirmSuccess() {
        let manager = GestureManager(clock: TestClock())
        manager.isZoomAvailableProvider = { false }
        var scales: [CGFloat] = []
        manager.onZoom = { scales.append($0) }

        manager.applyZoomPublic(fill: true)
        manager.pinchChanged(scale: 1.5, phase: .changed)

        XCTAssertFalse(manager.isZoomFilled)
        XCTAssertTrue(scales.isEmpty)
        XCTAssertNil(manager.hudModel.hud)
        XCTAssertEqual(
            manager.currentCapabilities().zoom,
            .unavailable(.notSupportedOnPlatform)
        )
    }

    func testGestureResetReturnsZoomStateAndDrawableToFit() {
        let manager = GestureManager(clock: TestClock())
        var scales: [CGFloat] = []
        manager.onZoom = { scales.append($0) }
        manager.applyZoomPublic(fill: true)

        manager.reset()

        XCTAssertFalse(manager.isZoomFilled)
        XCTAssertEqual(scales, [1.5, 0.5])
    }

    func testAccessibilityRefreshInvalidatesObservedLeaves() {
        let manager = GestureManager(clock: TestClock())
        var invalidationCount = 0
        let token = manager.objectWillChange.sink { invalidationCount += 1 }

        manager.refreshAccessibilityState()

        XCTAssertEqual(invalidationCount, 1)
        withExtendedLifetime(token) {}
    }

    func testKnownVoiceControlSuppressesChromeAutoHideAndGestureCoach() {
        let state = AssistiveTechnologyState(isVoiceControlRunning: true)

        XCTAssertTrue(state.suppressesAutoHide)
        XCTAssertTrue(state.suppressesCoach)
    }

    func testPictureInPictureFailureHasUserFacingDescription() {
        XCTAssertEqual(
            PlayerKitError.pictureInPictureFailed("The video is not ready.").errorDescription,
            "Picture in Picture couldn’t start."
        )
    }

    func testPictureInPictureRestorationMayCompleteAsynchronously() {
        let manager = PlayerManager.shared
        let original = manager.onPictureInPictureRestoreRequested
        defer { manager.onPictureInPictureRestoreRequested = original }

        var deferredCompletion: ((Bool) -> Void)?
        manager.onPictureInPictureRestoreRequested = { completion in
            deferredCompletion = completion
        }

        var restored: Bool?
        manager.onPictureInPictureRestoreRequested? { restored = $0 }
        XCTAssertNotNil(deferredCompletion)
        deferredCompletion?(true)
        XCTAssertEqual(restored, true)
    }

    #if os(macOS)
    func testMountingPointerHostDoesNotStealFirstResponder() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let existingResponder = PlayerKitFocusProbeView(frame: .zero)
        window.contentView?.addSubview(existingResponder)
        XCTAssertTrue(window.makeFirstResponder(existingResponder))

        window.contentView?.addSubview(PlayerKitPointerHostView(frame: .zero))

        XCTAssertTrue(window.firstResponder === existingResponder)
    }

    func testPlayerKeyboardShortcutsYieldToSystemModifierCommands() {
        XCTAssertTrue(PlayerKitPointerHostView.hasReservedShortcutModifier(.command))
        XCTAssertTrue(PlayerKitPointerHostView.hasReservedShortcutModifier(.control))
        XCTAssertTrue(PlayerKitPointerHostView.hasReservedShortcutModifier(.option))
        XCTAssertFalse(PlayerKitPointerHostView.hasReservedShortcutModifier(.shift))
        XCTAssertFalse(PlayerKitPointerHostView.hasReservedShortcutModifier([]))
    }
    #endif

    #if os(iOS)
    func testVLCPictureInPictureSeekabilityRequiresFiniteSeekableMedia() {
        XCTAssertTrue(
            VLCPlayerDrawableProxy.isFiniteSeekableMedia(
                isSeekable: true,
                durationMilliseconds: 60_000
            )
        )
        XCTAssertFalse(
            VLCPlayerDrawableProxy.isFiniteSeekableMedia(
                isSeekable: false,
                durationMilliseconds: 60_000
            )
        )
        XCTAssertFalse(
            VLCPlayerDrawableProxy.isFiniteSeekableMedia(
                isSeekable: true,
                durationMilliseconds: 0
            )
        )
    }
    #endif

    private func flushGestureHUD() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }
}

#if os(macOS)
private final class PlayerKitFocusProbeView: NSView {
    override var acceptsFirstResponder: Bool { true }
}
#endif
