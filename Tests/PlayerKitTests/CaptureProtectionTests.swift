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
}
#endif
