import CoreGraphics
import XCTest
@testable import PlayerKit
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AdaptiveControlsRegressionTests: XCTestCase {
    /// A surface too narrow for five transport controls moves the episode pair
    /// below the play/skip group rather than clipping it.
    ///
    /// The boundary moved outward when the transport stopped reserving 104pt
    /// for the info and lock buttons that used to flank it: a 375pt surface now
    /// has 345pt of room and fits the row, where before it was told it had 241
    /// and stacked. Narrow surfaces — Slide Over, a small embedded player —
    /// still stack.
    func testEpisodeTransportStacksOnlyOnSurfacesTooNarrowForTheRow() {
        for width: CGFloat in [280, 320] {
            let available = PlayerControlsView.effectiveTransportWidth(for: width)
            XCTAssertLessThan(available, MiddleControlsView.episodeRowMinimumWidth)
            XCTAssertEqual(
                MiddleControlsView.arrangement(availableWidth: available, contentType: .episode),
                .stacked,
                "\(width)pt cannot fit the five-control episode row"
            )
        }

        for width: CGFloat in [375, 700, 1120] {
            let available = PlayerControlsView.effectiveTransportWidth(for: width)
            XCTAssertGreaterThanOrEqual(available, MiddleControlsView.episodeRowMinimumWidth)
            XCTAssertEqual(
                MiddleControlsView.arrangement(availableWidth: available, contentType: .episode),
                .row,
                "\(width)pt fits all five controls on one line"
            )
        }

        // A movie has no episode pair, so it stays on one line at every width.
        for width: CGFloat in [280, 320, 375, 1120] {
            XCTAssertEqual(
                MiddleControlsView.arrangement(
                    availableWidth: PlayerControlsView.effectiveTransportWidth(for: width),
                    contentType: .movie
                ),
                .row
            )
        }
    }

    func testEpisodeTransportUsesOneRowWhenItsMeasuredControlsFit() {
        XCTAssertEqual(
            MiddleControlsView.arrangement(
                availableWidth: MiddleControlsView.episodeRowMinimumWidth,
                contentType: .episode
            ),
            .row
        )
    }

    /// The transport is given the full content width.
    ///
    /// It used to be handed `contentWidth - 104`, reserving space for the info
    /// and lock buttons that flanked it. Those moved into the top bar, and the
    /// leftover subtraction made this function non-monotonic across its own
    /// breakpoint — more surface, less reported width.
    func testTransportWidthIsTheContentWidthAndGrowsWithTheSurface() {
        for width: CGFloat in [280, 375, 700, 1120, 1920] {
            XCTAssertEqual(
                PlayerControlsView.effectiveTransportWidth(for: width),
                width - (PlayerControlsView.contentPadding(for: width) * 2)
            )
        }

        let widths: [CGFloat] = [200, 280, 287, 288, 320, 560, 1120, 2560]
        let reported = widths.map(PlayerControlsView.effectiveTransportWidth(for:))
        XCTAssertEqual(reported, reported.sorted(), "A wider surface must never report less room")
    }

    #if canImport(UIKit)
    func testCaptureShieldHasSightedDynamicTypeExplanation() throws {
        let host = PlayerKitProtectedContentView(frame: .zero)
        host.applyCaptureState(true)

        let label = try XCTUnwrap(
            allSubviews(of: host)
                .compactMap { $0 as? UILabel }
                .first { $0.text == "Video hidden while screen sharing is active" }
        )
        XCTAssertFalse(label.isHidden)
        XCTAssertEqual(label.textColor, .white)
        XCTAssertTrue(label.adjustsFontForContentSizeCategory)
        XCTAssertEqual(label.numberOfLines, 0)
    }

    private func allSubviews(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap(allSubviews)
    }
    #endif
}
