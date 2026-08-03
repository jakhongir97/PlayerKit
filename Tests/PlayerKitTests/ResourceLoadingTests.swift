import XCTest
@testable import PlayerKit

@MainActor
final class ResourceLoadingTests: XCTestCase {
    func testTransportImagesLoadFromSwiftPMBundle() {
        for name in ["play", "pause", "prev", "next", "chromecast"] {
            XCTAssertNotNil(PKImage.fromFramework(named: name), "Missing bundled image: \(name)")
        }
    }
}
