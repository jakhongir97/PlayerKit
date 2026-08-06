import XCTest
@testable import PlayerKit

/// The resolution order is what screenshot tooling relies on: a script can set a
/// user default (or pass `-PlayerKitCaptureProtectionPolicy`, which lands in the
/// same argument domain) without the app knowing anything about it.
final class CaptureProtectionPolicyTests: XCTestCase {
    private let suiteName = "PlayerKitCaptureProtectionPolicyTests"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultsToFullProtectionWhenNothingIsConfigured() {
        XCTAssertEqual(
            PlayerCaptureProtectionPolicy.resolvedDefault(defaults: defaults, environment: [:]),
            .automatic
        )
    }

    func testUserDefaultSelectsThePolicy() {
        defaults.set("blackOutVideo", forKey: PlayerCaptureProtectionPolicy.userDefaultsKey)

        XCTAssertEqual(
            PlayerCaptureProtectionPolicy.resolvedDefault(defaults: defaults, environment: [:]),
            .blackOutVideo
        )
    }

    func testEnvironmentSelectsThePolicyWhenNoDefaultIsSet() {
        XCTAssertEqual(
            PlayerCaptureProtectionPolicy.resolvedDefault(
                defaults: defaults,
                environment: [PlayerCaptureProtectionPolicy.environmentKey: "allowCapture"]
            ),
            .allowCapture
        )
    }

    func testUserDefaultWinsOverEnvironment() {
        defaults.set("allowCapture", forKey: PlayerCaptureProtectionPolicy.userDefaultsKey)

        XCTAssertEqual(
            PlayerCaptureProtectionPolicy.resolvedDefault(
                defaults: defaults,
                environment: [PlayerCaptureProtectionPolicy.environmentKey: "blackOutVideo"]
            ),
            .allowCapture
        )
    }

    /// A misspelled flag must not quietly leave the player at full protection and
    /// look like the blackout feature is broken — it falls back, but only after
    /// every reasonable spelling has been tried.
    func testAcceptsTheSpellingsAShellScriptIsLikelyToUse() {
        let expectations: [String: PlayerCaptureProtectionPolicy] = [
            "automatic": .automatic,
            "AUTO": .automatic,
            "protect-window": .automatic,
            "blackOutVideo": .blackOutVideo,
            "black-out-video": .blackOutVideo,
            "  BlackOut  ": .blackOutVideo,
            "capture_safe": .blackOutVideo,
            "hide-video": .blackOutVideo,
            "allowCapture": .allowCapture,
            "off": .allowCapture,
            "none": .allowCapture,
        ]

        for (raw, expected) in expectations {
            XCTAssertEqual(
                PlayerCaptureProtectionPolicy(lenient: raw),
                expected,
                "\(raw) should resolve to \(expected)"
            )
        }
    }

    func testUnrecognizedValueFallsBackToFullProtection() {
        defaults.set("nonsense", forKey: PlayerCaptureProtectionPolicy.userDefaultsKey)

        XCTAssertNil(PlayerCaptureProtectionPolicy(lenient: "nonsense"))
        XCTAssertEqual(
            PlayerCaptureProtectionPolicy.resolvedDefault(defaults: defaults, environment: [:]),
            .automatic
        )
    }
}
