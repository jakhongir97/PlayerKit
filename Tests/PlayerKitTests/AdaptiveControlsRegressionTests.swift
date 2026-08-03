import CoreGraphics
import XCTest
@testable import PlayerKit
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AdaptiveControlsRegressionTests: XCTestCase {
    func testEpisodeTransportStacksAtCompactAndSlideOverWidths() {
        for width: CGFloat in [320, 375] {
            let available = PlayerControlsView.effectiveTransportWidth(for: width)

            XCTAssertGreaterThanOrEqual(
                available,
                MiddleControlsView.compactTransportMinimumWidth,
                "Side actions must move to their own row before transport clips at \(width)pt"
            )
            XCTAssertEqual(
                MiddleControlsView.arrangement(
                    availableWidth: available,
                    contentType: .episode
                ),
                .stacked
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

    func testVeryNarrowSurfaceMovesSideActionsBelowTransport() {
        XCTAssertTrue(PlayerControlsView.separatesSideControls(for: 280))
        XCTAssertGreaterThanOrEqual(
            PlayerControlsView.effectiveTransportWidth(for: 280),
            MiddleControlsView.compactTransportMinimumWidth
        )
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
