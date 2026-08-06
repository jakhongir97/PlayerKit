#if canImport(AppKit) && !canImport(UIKit)
import AppKit
import XCTest
@testable import PlayerKit

/// End-to-end proof of the thing the policy actually promises: that a window
/// hosting the player can or cannot be screenshotted.
///
/// Everything else about capture protection can be asserted from `sharingType`,
/// but `sharingType` is not trustworthy as an observation — the value reported
/// back by `CGWindowListCopyWindowInfo(kCGWindowSharingState)` can lag the real
/// state of a live window, which is exactly how "it looks like it worked" turns
/// into a screenshot that still fails. `screencapture` is the oracle.
///
/// Opt-in: it needs a GUI login session and Screen Recording permission for the
/// test runner, neither of which a CI machine has. Run it with
/// `PLAYERKIT_RUN_CAPTURE_INTEGRATION=1 swift test --filter CaptureProtectionScreenshot`.
@MainActor
final class CaptureProtectionScreenshotTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PLAYERKIT_RUN_CAPTURE_INTEGRATION"] == "1",
            "Set PLAYERKIT_RUN_CAPTURE_INTEGRATION=1 to run the screencapture integration tests."
        )
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    override func tearDown() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        super.tearDown()
    }

    func testPolicyDecidesWhetherTheHostWindowCanBeScreenshotted() throws {
        // A window with no player in it at all. If this one cannot be captured
        // the environment is the problem, not the policy.
        let control = makeVisibleWindow()
        try XCTSkipUnless(
            canScreenshot(control),
            "screencapture cannot read an ordinary window — grant the test runner Screen Recording permission."
        )

        let window = makeVisibleWindow()
        let host = PlayerKitProtectedContentView(frame: window.contentLayoutRect)
        let content = NSView(frame: window.contentLayoutRect)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.systemRed.cgColor
        host.setProtectedContentView(content)
        window.contentView?.addSubview(host)
        settle()

        XCTAssertFalse(
            canScreenshot(window),
            "`.automatic` must take the whole window out of capture — this is the behaviour being traded away"
        )

        host.setCaptureProtectionPolicy(.blackOutVideo)
        settle()
        XCTAssertTrue(
            canScreenshot(window),
            "`.blackOutVideo` must hand the window back to screen capture"
        )
        XCTAssertTrue(host.isContentHiddenForCapture)

        host.setCaptureProtectionPolicy(.allowCapture)
        settle()
        XCTAssertTrue(canScreenshot(window), "`.allowCapture` must leave the window capturable")
        XCTAssertFalse(host.isContentHiddenForCapture)

        host.setCaptureProtectionPolicy(.automatic)
        settle()
        XCTAssertFalse(
            canScreenshot(window),
            "returning to `.automatic` must re-protect the window — the screenshot script relies on this restore"
        )
    }

    // MARK: Helpers

    private func makeVisibleWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 40, y: 40, width: 360, height: 220),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.systemGreen.cgColor
        window.orderFront(nil)
        windows.append(window)
        settle()
        return window
    }

    /// The window server needs a turn of the run loop before a freshly ordered
    /// window — or a freshly changed `sharingType` — is visible to a capture.
    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
    }

    private func canScreenshot(_ window: NSWindow) -> Bool {
        let destination = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("playerkit-capture-\(window.windowNumber).png")
        try? FileManager.default.removeItem(at: destination)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-l", "\(window.windowNumber)", "-o", "-x", destination.path]
        process.standardError = Pipe()
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            XCTFail("could not run screencapture: \(error)")
            return false
        }
        process.waitUntilExit()

        let wrote = FileManager.default.fileExists(atPath: destination.path)
        try? FileManager.default.removeItem(at: destination)
        return process.terminationStatus == 0 && wrote
    }
}
#endif
