#if canImport(AppKit) && !canImport(UIKit)
import AppKit
import XCTest
@testable import PlayerKit

/// `PlayerView` keys the rendering subtree on `playerGeneration`, so every player
/// swap makes SwiftUI build a fresh `PlayerKitProtectedContentView` and dismantle
/// the previous one. SwiftUI creates the replacement *before* tearing down what it
/// replaces, so the outgoing host is asked to drop its content while that same
/// player view is already living in the incoming host.
///
/// The old code removed the player view from whatever superview it happened to
/// have, which pulled the video straight back out of the live host and left a
/// `PlayerKitProtectedContentView` showing nothing but its own black backing
/// layer — a black player window with audio playing normally.
@MainActor
final class ProtectedContentHandoverTests: XCTestCase {

    /// The exact SwiftUI ordering: make the new host, then dismantle the old one.
    func testDismantlingTheOutgoingHostLeavesContentInTheIncomingHost() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))

        let outgoing = PlayerKitProtectedContentView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        outgoing.setProtectedContentView(content)
        XCTAssertTrue(content.isDescendant(of: outgoing), "precondition: the first host owns the content")

        let incoming = PlayerKitProtectedContentView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        incoming.setProtectedContentView(content)
        XCTAssertTrue(content.isDescendant(of: incoming), "the new host adopts the content")

        // SwiftUI now dismantles the host it replaced.
        outgoing.setProtectedContentView(nil)

        XCTAssertTrue(
            content.isDescendant(of: incoming),
            "the outgoing host tore the player view out of the live host — this is the black player"
        )
        XCTAssertEqual(incoming.subviews.count, 1, "the live host must still be rendering the player view")
        XCTAssertTrue(outgoing.subviews.isEmpty, "the retired host must not keep the player view")
    }

    /// A layout pass must not let a retired host steal the content back.
    func testLayoutOnARetiredHostDoesNotStealContentBack() {
        let content = NSView(frame: .zero)

        let outgoing = PlayerKitProtectedContentView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        outgoing.setProtectedContentView(content)

        let incoming = PlayerKitProtectedContentView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        incoming.setProtectedContentView(content)

        outgoing.layoutSubtreeIfNeeded()

        XCTAssertTrue(content.isDescendant(of: incoming), "a stale host must not reclaim the player view")
    }

    /// The ordinary single-host path still installs and still tears down.
    func testSingleHostInstallsAndReleasesContent() {
        let content = NSView(frame: .zero)
        let host = PlayerKitProtectedContentView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))

        host.setProtectedContentView(content)
        XCTAssertEqual(host.subviews.count, 1)
        XCTAssertEqual(content.superview, host)

        host.setProtectedContentView(nil)
        XCTAssertTrue(host.subviews.isEmpty, "tearing down the only host must release the player view")
        XCTAssertNil(content.superview)
    }

    /// An orphaned player view is recovered on the next layout pass, matching the
    /// self-healing the UIKit branch has always had.
    func testOrphanedContentIsReadoptedOnLayout() {
        let content = NSView(frame: .zero)
        let host = PlayerKitProtectedContentView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        host.setProtectedContentView(content)

        content.removeFromSuperview()
        XCTAssertNil(content.superview, "precondition: the player view is orphaned")

        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(content.superview, host, "the host should re-adopt a player view nothing else owns")
    }
}
#endif
