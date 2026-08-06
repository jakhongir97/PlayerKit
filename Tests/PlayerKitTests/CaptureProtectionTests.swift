#if canImport(UIKit)
import UIKit
import XCTest
@testable import PlayerKit

@MainActor
final class CaptureProtectionTests: XCTestCase {
    func testActiveCaptureHidesAndRestoresProtectedContent() {
        let host = PlayerKitProtectedContentView(frame: .zero)
        let content = UIView(frame: .zero)
        host.setProtectedContentView(content)

        host.applyCaptureState(true)
        XCTAssertTrue(host.isContentHiddenForCapture)
        XCTAssertTrue(content.accessibilityElementsHidden)

        host.applyCaptureState(false)
        XCTAssertFalse(host.isContentHiddenForCapture)
        XCTAssertFalse(content.accessibilityElementsHidden)
    }

    /// The blackout policy is not a reaction to a capture — it holds the shield
    /// down unconditionally, which is what makes a screenshot deterministic.
    func testBlackOutVideoShieldsRegardlessOfCaptureState() {
        let host = PlayerKitProtectedContentView(frame: .zero)
        host.setProtectedContentView(UIView(frame: .zero))

        host.setCaptureProtectionPolicy(.blackOutVideo)
        XCTAssertTrue(host.isContentHiddenForCapture)

        host.applyCaptureState(false)
        XCTAssertTrue(host.isContentHiddenForCapture)
    }

    func testAllowCaptureNeverShieldsEvenWhileTheScreenIsCaptured() {
        let host = PlayerKitProtectedContentView(frame: .zero)
        let content = UIView(frame: .zero)
        host.setProtectedContentView(content)

        host.setCaptureProtectionPolicy(.allowCapture)
        host.applyCaptureState(true)

        XCTAssertFalse(host.isContentHiddenForCapture)
        XCTAssertFalse(content.accessibilityElementsHidden)
    }

    /// The secure-text canvas is the thing that blanks the video in an iOS
    /// screenshot, so opting out of protection has to take the player view back
    /// out of it — leaving it inside would keep the video black in captures.
    func testAllowCaptureMovesContentOutOfTheSecureCanvas() {
        let host = PlayerKitProtectedContentView(frame: .zero)
        let content = UIView(frame: .zero)
        host.setProtectedContentView(content)

        XCTAssertFalse(content.superview === host, "protected content should start inside the secure canvas")

        host.setCaptureProtectionPolicy(.allowCapture)
        XCTAssertTrue(content.superview === host)

        host.setCaptureProtectionPolicy(.automatic)
        XCTAssertFalse(content.superview === host)
    }
}
#elseif canImport(AppKit)
import AppKit
import XCTest
@testable import PlayerKit

@MainActor
final class CaptureProtectionTests: XCTestCase {
    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.sharingType = .readOnly
        return window
    }

    private func mount(
        _ host: PlayerKitProtectedContentView,
        in window: NSWindow
    ) {
        host.frame = window.contentLayoutRect
        window.contentView?.addSubview(host)
    }

    func testAutomaticPolicyTakesTheWholeHostWindowOutOfCapture() {
        let window = makeWindow()
        let host = PlayerKitProtectedContentView(frame: .zero)
        let content = NSView(frame: .zero)
        host.setProtectedContentView(content)
        mount(host, in: window)

        XCTAssertEqual(window.sharingType, .none)
        XCTAssertFalse(host.isContentHiddenForCapture)
        XCTAssertFalse(content.isHidden)
    }

    /// The point of the blackout policy: the window goes back to being
    /// capturable — `screencapture` on a `.none` window fails outright rather
    /// than returning a black image — and the video is blanked instead.
    func testBlackOutVideoReturnsTheWindowToCaptureAndBlanksTheVideo() {
        let window = makeWindow()
        let host = PlayerKitProtectedContentView(frame: .zero)
        let content = NSView(frame: .zero)
        host.setProtectedContentView(content)
        mount(host, in: window)
        XCTAssertEqual(window.sharingType, .none)

        host.setCaptureProtectionPolicy(.blackOutVideo)

        XCTAssertEqual(window.sharingType, .readOnly)
        XCTAssertTrue(host.isContentHiddenForCapture)
        XCTAssertTrue(content.isHidden)
    }

    func testAllowCaptureLeavesBothTheWindowAndTheVideoAlone() {
        let window = makeWindow()
        let host = PlayerKitProtectedContentView(frame: .zero)
        let content = NSView(frame: .zero)
        host.setProtectedContentView(content)
        mount(host, in: window)

        host.setCaptureProtectionPolicy(.allowCapture)

        XCTAssertEqual(window.sharingType, .readOnly)
        XCTAssertFalse(host.isContentHiddenForCapture)
        XCTAssertFalse(content.isHidden)
    }

    func testSwitchingBackToAutomaticReprotectsTheWindow() {
        let window = makeWindow()
        let host = PlayerKitProtectedContentView(frame: .zero)
        let content = NSView(frame: .zero)
        host.setProtectedContentView(content)
        mount(host, in: window)

        host.setCaptureProtectionPolicy(.blackOutVideo)
        XCTAssertEqual(window.sharingType, .readOnly)

        host.setCaptureProtectionPolicy(.automatic)
        XCTAssertEqual(window.sharingType, .none)
        XCTAssertFalse(host.isContentHiddenForCapture)
        XCTAssertFalse(content.isHidden)
    }

    /// A policy chosen before the view ever reaches a window must not protect it
    /// on the way in — this is the launch-argument path.
    func testPolicySetBeforeMountingIsHonouredOnMount() {
        let window = makeWindow()
        let host = PlayerKitProtectedContentView(frame: .zero)
        host.setCaptureProtectionPolicy(.blackOutVideo)
        host.setProtectedContentView(NSView(frame: .zero))
        mount(host, in: window)

        XCTAssertEqual(window.sharingType, .readOnly)
        XCTAssertTrue(host.isContentHiddenForCapture)
    }

    func testRemovingTheViewRestoresTheOriginalSharingType() {
        let window = makeWindow()
        let host = PlayerKitProtectedContentView(frame: .zero)
        host.setProtectedContentView(NSView(frame: .zero))
        mount(host, in: window)
        XCTAssertEqual(window.sharingType, .none)

        host.removeFromSuperview()

        XCTAssertEqual(window.sharingType, .readOnly)
    }

    func testCaptureShieldRendersTheHostSuppliedMessage() throws {
        let host = PlayerKitProtectedContentView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        host.setProtectedContentView(NSView(frame: .zero))
        host.setCaptureMessage("Видео скрыто во время записи экрана")
        host.setCaptureProtectionPolicy(.blackOutVideo)

        let label = try XCTUnwrap(
            allSubviews(of: host)
                .compactMap { $0 as? NSTextField }
                .first { $0.stringValue == "Видео скрыто во время записи экрана" }
        )
        XCTAssertEqual(label.textColor, .white)
        XCTAssertEqual(label.maximumNumberOfLines, 0)
        XCTAssertFalse(label.isHidden)
        // Hidden ancestors would make the message invisible even though the
        // label itself is not hidden.
        XCTAssertFalse(label.superview?.isHidden ?? true)
    }

    /// The shield only works if it is above the video. `install` re-parents the
    /// player view on every handover, so ordering has to survive that.
    func testShieldStaysAboveTheVideoAfterAContentHandover() {
        let host = PlayerKitProtectedContentView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        host.setCaptureProtectionPolicy(.blackOutVideo)
        host.setProtectedContentView(NSView(frame: .zero))

        let replacement = NSView(frame: .zero)
        host.setProtectedContentView(replacement)
        host.layoutSubtreeIfNeeded()

        let shield = try? XCTUnwrap(
            host.subviews.first { view in
                allSubviews(of: view).contains { ($0 as? NSTextField) != nil }
            }
        )
        XCTAssertNotNil(shield)
        XCTAssertTrue(host.subviews.last === shield)
        XCTAssertTrue(replacement.isHidden)
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(allSubviews)
    }
}
#endif
