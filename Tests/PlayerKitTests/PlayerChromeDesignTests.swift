import CoreGraphics
import SwiftUI
import XCTest
@testable import PlayerKit

/// Pins the invariants the chrome redesign rests on.
///
/// These are not "the button is blue" assertions — they are the geometric and
/// structural properties that, when they broke, produced the scattered-pills
/// look: a bottom bar that centred itself instead of spanning, breakpoints that
/// undercounted the controls they were sizing for, and per-view constants that
/// drifted apart from each other.
@MainActor
final class PlayerChromeDesignTests: XCTestCase {

    // MARK: - The bar spans

    /// The regression that made the chrome look unlaid-out.
    ///
    /// The bottom bar was a `ViewThatFits` whose candidate carried
    /// `.fixedSize(horizontal: true, vertical: false)`. `fixedSize` applies to
    /// the row that is *chosen*, not only to the measurement, so the bar was
    /// laid out at its content width and centred — its `Spacer` collapsed and
    /// the controls bunched into the middle with dead space at both edges. A
    /// width comparison cannot do that, and unlike `ViewThatFits` it can be
    /// asserted here.
    func testBottomBarUsesOneSpanningRowAtOrdinaryPlayerWidths() {
        // The window the macOS player actually opens at.
        let contentWidth = 1120 - (PlayerControlsView.contentPadding(for: 1120) * 2)
        XCTAssertTrue(BottomControlsView.usesSingleRow(availableWidth: contentWidth))
    }

    func testBottomBarStacksOnlyWhenTheClustersCannotShareALine() {
        XCTAssertFalse(
            BottomControlsView.usesSingleRow(
                availableWidth: BottomControlsView.singleRowMinimumWidth - 1
            )
        )
        XCTAssertTrue(
            BottomControlsView.usesSingleRow(
                availableWidth: BottomControlsView.singleRowMinimumWidth
            )
        )
    }

    // MARK: - Breakpoints describe the controls they gate

    /// The transport breakpoints used to be hand-written numbers (296 and 172)
    /// justified by a comment describing controls at sizes the code no longer
    /// used, so the row layout was chosen at widths where it could not fit.
    /// Deriving them from the same metrics the controls render at means the two
    /// cannot drift again.
    func testTransportBreakpointsMatchTheControlsTheyMeasure() {
        let secondary = PlayerChromeMetrics.secondaryControlDiameter
        let primary = PlayerChromeMetrics.primaryControlDiameter
        let gap = PlayerChromeMetrics.spacingM

        XCTAssertEqual(
            MiddleControlsView.compactTransportMinimumWidth,
            (secondary * 2) + primary + (gap * 2),
            "Skip / play / skip plus the gaps between them"
        )
        XCTAssertEqual(
            MiddleControlsView.episodeRowMinimumWidth,
            (secondary * 4) + primary + (gap * 4),
            "…plus the previous/next pair and their gaps"
        )
        XCTAssertGreaterThan(
            MiddleControlsView.episodeRowMinimumWidth,
            MiddleControlsView.compactTransportMinimumWidth
        )
    }

    /// The episode row must actually fit in the width that is declared to be
    /// enough for it — the property the old constants got wrong.
    func testEpisodeRowFitsInsideItsOwnMinimumWidth() {
        let measured = (PlayerChromeMetrics.secondaryControlDiameter * 4)
            + PlayerChromeMetrics.primaryControlDiameter
            + (PlayerChromeMetrics.spacingM * 4)
        XCTAssertLessThanOrEqual(measured, MiddleControlsView.episodeRowMinimumWidth)
        XCTAssertEqual(
            MiddleControlsView.arrangement(
                availableWidth: measured,
                contentType: .episode
            ),
            .row
        )
    }

    // MARK: - One size ramp, one spacing scale

    /// Three control tiers, strictly ordered. The chrome previously shipped
    /// eleven diameters, including a 44pt bare glyph sitting between two 60pt
    /// glass discs in the same row.
    func testControlDiametersFormOneOrderedRamp() {
        XCTAssertGreaterThan(
            PlayerChromeMetrics.primaryControlDiameter,
            PlayerChromeMetrics.secondaryControlDiameter
        )
        XCTAssertGreaterThan(
            PlayerChromeMetrics.secondaryControlDiameter,
            PlayerChromeMetrics.barControlDiameter
        )
    }

    /// Everything a finger or cursor has to hit is at least 44pt, including the
    /// deliberately small bar icons, which grow their target rather than their
    /// visible disc.
    func testEverySecondaryControlClearsTheMinimumTarget() {
        XCTAssertGreaterThanOrEqual(
            PlayerChromeMetrics.secondaryControlDiameter,
            PlayerChromeMetrics.minimumHitTarget
        )
        XCTAssertGreaterThanOrEqual(
            PlayerChromeMetrics.barItemHeight,
            PlayerChromeMetrics.minimumHitTarget
        )
    }

    func testSpacingScaleIsAStrictFourPointRamp() {
        let scale = [
            PlayerChromeMetrics.spacingXS,
            PlayerChromeMetrics.spacingS,
            PlayerChromeMetrics.spacingM,
            PlayerChromeMetrics.spacingL,
            PlayerChromeMetrics.spacingXL,
        ]
        XCTAssertEqual(scale, scale.sorted())
        for step in scale {
            XCTAssertEqual(step.truncatingRemainder(dividingBy: 4), 0, "\(step) is off the scale")
        }
    }

    /// The glyph-to-control ratio is what makes a 38pt bar icon and a 64pt play
    /// glyph read as one icon set rather than as two.
    func testGlyphSizeTracksItsControlProportionally() {
        let small = PlayerChromeTypography.glyphSize(for: PlayerChromeMetrics.barControlDiameter)
        let large = PlayerChromeTypography.glyphSize(for: PlayerChromeMetrics.primaryControlDiameter)
        XCTAssertGreaterThan(large, small)
        XCTAssertEqual(
            large / PlayerChromeMetrics.primaryControlDiameter,
            small / PlayerChromeMetrics.barControlDiameter,
            accuracy: 0.02
        )
    }

    // MARK: - The lock still has a way out

    /// The lock moved from a floating control at the player's mid-right edge
    /// into the top bar's action group. That is only safe if it keeps
    /// outliving the chrome around it: everything else in the row goes when the
    /// lock engages, and the unlock button does not.
    func testUnlockAffordanceOutlivesTheChromeItSitsIn() {
        let manager = PlayerManager.shared
        defer { manager.tearDown() }
        manager.playerItem = PlayerItem(
            title: "Episode",
            url: URL(string: "https://example.com/a.m3u8")!
        )
        let top = TopControlsView(playerManager: manager)
        let controls = PlayerControlsView(playerManager: manager, presentationPolicy: .init())

        manager.areControlsVisible = true
        manager.isLocked = false
        XCTAssertTrue(top.showsChrome)
        XCTAssertTrue(top.showsUnlockControl)
        XCTAssertTrue(controls.showsScrubber)

        manager.isLocked = true
        XCTAssertFalse(top.showsChrome, "Everything else in the row must go")
        XCTAssertTrue(top.showsUnlockControl, "…except the way back out")
        XCTAssertFalse(controls.showsScrubber, "A locked player must not be scrubbable")

        // Chrome hidden entirely: even the unlock goes, because a tap anywhere
        // brings the chrome back first.
        manager.areControlsVisible = false
        XCTAssertFalse(top.showsUnlockControl)

        manager.isLocked = false
    }

    // MARK: - Host theming

    /// PlayerKit had no way at all to receive brand styling, which is why the
    /// host had to paint its own skip button over the player rather than let
    /// PlayerKit draw one that matched.
    func testAppearanceDefaultsToNeutralAndIsHostOverridable() {
        let manager = PlayerManager.shared
        defer {
            manager.appearance = .default
            manager.tearDown()
        }

        XCTAssertEqual(manager.appearance, .default)
        XCTAssertEqual(PlayerAppearance.default.accent, .white)

        let branded = PlayerAppearance(accent: .green, accentForeground: .black)
        manager.appearance = branded
        XCTAssertEqual(manager.appearance, branded)
        XCTAssertNotEqual(manager.appearance, .default)
    }

    // MARK: - Chrome insets

    /// The inset is clamped at both ends so an embedded player is not padded
    /// like a full-screen one, and a very wide window does not push the chrome
    /// into the middle of the picture.
    func testContentInsetIsClampedAtBothEnds() {
        XCTAssertEqual(PlayerChromeMetrics.contentInset(for: 100), PlayerChromeMetrics.spacingM)
        XCTAssertEqual(PlayerChromeMetrics.contentInset(for: 4000), 32)
        XCTAssertEqual(
            PlayerControlsView.contentPadding(for: 1120),
            PlayerChromeMetrics.contentInset(for: 1120)
        )
    }
}
