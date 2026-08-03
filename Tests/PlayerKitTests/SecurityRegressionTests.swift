import Foundation
import XCTest
@testable import PlayerKit

#if os(macOS)
final class SecurityRegressionTests: XCTestCase {
    func testDesktopVLCRejectsCodeNotSignedByVideoLAN() {
        let testBundle = Bundle(for: type(of: self)).bundleURL

        XCTAssertFalse(DesktopVLCCodeSignature.isTrustedBundle(at: testBundle))
    }
}
#endif
