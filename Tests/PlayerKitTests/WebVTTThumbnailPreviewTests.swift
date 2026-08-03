import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import PlayerKit

@MainActor
final class WebVTTThumbnailPreviewTests: XCTestCase {
    func testStandardFixtureParsesRelativeSpriteCropsAndHalfOpenBoundaries() throws {
        let fixture = """
        \u{feff}WEBVTT - redacted fixture\r
        \r
        NOTE generated thumbnail track\r
        this block is ignored\r
        \r
        first-cue\r
        00:00.000 --> 00:05.000 align:start\r
        sprites/sheet.jpg?token=redacted#xywh=pixel:0,0,160,90\r
        \r
        00:05.000 --> 00:10.000 position:50%\r
        full.jpg\r
        """
        let baseURL = try XCTUnwrap(URL(string: "https://fixtures.invalid/media/thumbs.vtt?key=redacted"))

        let cues = WebVTTThumbnailParser.parse(fixture, baseURL: baseURL)

        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].startTime, 0)
        XCTAssertEqual(cues[0].endTime, 5)
        XCTAssertEqual(
            cues[0].imageURL.absoluteString,
            "https://fixtures.invalid/media/sprites/sheet.jpg?token=redacted"
        )
        XCTAssertEqual(cues[0].cropRect, CGRect(x: 0, y: 0, width: 160, height: 90))
        XCTAssertEqual(
            cues[1].imageURL.absoluteString,
            "https://fixtures.invalid/media/full.jpg"
        )
        XCTAssertNil(cues[1].cropRect)

        XCTAssertEqual(WebVTTThumbnailParser.cue(at: 0, in: cues)?.identifier, 0)
        XCTAssertEqual(WebVTTThumbnailParser.cue(at: 4.999, in: cues)?.identifier, 0)
        XCTAssertEqual(WebVTTThumbnailParser.cue(at: 5, in: cues)?.identifier, 1)
        XCTAssertNil(WebVTTThumbnailParser.cue(at: 10, in: cues))
        XCTAssertNil(WebVTTThumbnailParser.cue(at: .nan, in: cues))
    }

    func testMalformedAndUnavailableManifestsFailClosed() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://fixtures.invalid/thumbs/index.vtt"))
        let fixture = """
        WEBVTT

        00:bad --> 00:05.000
        bad-time.jpg

        00:05.000 --> 00:10.000
        sprite.jpg#xywh=-1,0,10,10

        00:10.000 --> 00:15.000
        sprite.jpg#xywh=0,0,20,bad,10

        00:15.000 --> 00:12.000
        reversed.jpg

        valid
        00:20.000 --> 00:25.000 line:20%
        valid.jpg#xywh=0,0,20,10
        """

        let cues = WebVTTThumbnailParser.parse(fixture, baseURL: baseURL)

        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues.first?.startTime, 20)
        XCTAssertTrue(WebVTTThumbnailParser.parse("not webvtt", baseURL: baseURL).isEmpty)
        XCTAssertTrue(WebVTTThumbnailParser.parse(Data(), baseURL: baseURL).isEmpty)
        XCTAssertTrue(WebVTTThumbnailParser.parse(Data([0xff]), baseURL: baseURL).isEmpty)
    }

    func testSpriteCropAndResponseBufferStayWithinBounds() throws {
        let image = try makeImage(width: 100, height: 100)

        let cropped = try XCTUnwrap(
            WebVTTThumbnailCropper.crop(image, to: CGRect(x: 10, y: 10, width: 4, height: 3))
        )
        XCTAssertEqual(cropped.width, 4)
        XCTAssertEqual(cropped.height, 3)
        XCTAssertFalse(image.dataProvider === cropped.dataProvider)
        XCTAssertLessThan(
            try XCTUnwrap(WebVTTThumbnailProcessor.cost(cropped)),
            try XCTUnwrap(WebVTTThumbnailProcessor.cost(image))
        )
        let clipped = try XCTUnwrap(
            WebVTTThumbnailCropper.crop(image, to: CGRect(x: 99, y: 0, width: 4, height: 1))
        )
        XCTAssertEqual(clipped.width, 1)
        XCTAssertNil(
            WebVTTThumbnailCropper.crop(image, to: CGRect(x: 101, y: 0, width: 1, height: 1))
        )
        XCTAssertNil(
            WebVTTThumbnailCropper.crop(image, to: CGRect(x: 0, y: 0, width: 0, height: 1))
        )

        var buffer = BoundedThumbnailDataBuffer(limit: 4)
        XCTAssertTrue(buffer.append(Data([0, 1])))
        XCTAssertTrue(buffer.append(Data([2, 3])))
        XCTAssertEqual(buffer.data.count, 4)
        XCTAssertFalse(buffer.append(Data([4])))
        XCTAssertTrue(buffer.data.isEmpty, "Oversized payload bytes must be released immediately")
    }

    func testBoundedTransportAcceptsExactLimitAndRejectsStatusLengthAndChunkOverflow() throws {
        for path in ["success", "final-url", "status", "length", "overflow", "no-response"] {
            let completed = expectation(description: path)
            completed.assertForOverFulfill = true
            let url = try XCTUnwrap(URL(string: "https://fixtures.invalid/\(path)"))
            let request = BoundedThumbnailDataRequest(
                url: url,
                byteLimit: 4,
                protocolClasses: [ThumbnailTransportURLProtocol.self]
            ) { data, finalURL in
                if path == "success" || path == "final-url" {
                    XCTAssertEqual(data, Data([0, 1, 2, 3]))
                    XCTAssertEqual(
                        finalURL,
                        path == "final-url"
                            ? URL(string: "https://cdn.invalid/thumbs/final.vtt")
                            : url
                    )
                } else {
                    XCTAssertNil(data)
                    XCTAssertNil(finalURL)
                }
                completed.fulfill()
            }

            request.resume()
            wait(for: [completed], timeout: 1)
            withExtendedLifetime(request) {}
        }
    }

    func testBoundedTransportCancellationStopsProtocolAndSuppressesCallback() throws {
        let url = try XCTUnwrap(URL(string: "https://fixtures.invalid/cancel"))
        let started = expectation(
            forNotification: ThumbnailTransportURLProtocol.started,
            object: nil
        ) { ($0.userInfo?["url"] as? URL) == url }
        let stopped = expectation(
            forNotification: ThumbnailTransportURLProtocol.stopped,
            object: nil
        ) { ($0.userInfo?["url"] as? URL) == url }
        let callback = expectation(description: "cancelled callback")
        callback.isInverted = true
        callback.assertForOverFulfill = true
        let request = BoundedThumbnailDataRequest(
            url: url,
            byteLimit: 4,
            protocolClasses: [ThumbnailTransportURLProtocol.self]
        ) { _, _ in callback.fulfill() }

        request.resume()
        wait(for: [started], timeout: 1)
        request.cancel()
        wait(for: [stopped, callback], timeout: 0.2)
        withExtendedLifetime(request) {}
    }

    func testProcessorHonorsSelfCancellation() async throws {
        let processor = WebVTTThumbnailProcessor()
        let baseURL = try XCTUnwrap(URL(string: "https://fixtures.invalid/thumbs.vtt"))
        let data = Data("WEBVTT\n\n00:00.000 --> 00:01.000\nframe.jpg\n".utf8)

        let result = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await processor.parse(data, baseURL: baseURL)
        }.value

        XCTAssertNil(result)
    }

    func testImageIOPreflightRejectsOversizeAndNormalizesOrientation() async throws {
        XCTAssertEqual(
            WebVTTThumbnailProcessor.rgbaCost(width: 4_096, height: 4_096),
            WebVTTThumbnailProcessor.defaultDecodedByteLimit
        )
        XCTAssertNil(WebVTTThumbnailProcessor.rgbaCost(width: Int.max, height: 2))

        let fixture = try makeOrientedTIFF()
        let rejected = await WebVTTThumbnailProcessor(decodedByteLimit: 7).decode(fixture)
        XCTAssertNil(rejected, "The 2 x 1 RGBA preflight must reject an 8-byte image at a 7-byte limit")

        let decodedResult = await WebVTTThumbnailProcessor().decode(fixture)
        let decoded = try XCTUnwrap(decodedResult)
        XCTAssertEqual(decoded.image.width, 1)
        XCTAssertEqual(decoded.image.height, 2)
        XCTAssertLessThanOrEqual(decoded.cost, WebVTTThumbnailProcessor.defaultDecodedByteLimit)
    }

    func testOwnerAndRequestGenerationsRejectStaleWorkAndMetadataSurvivesCopies() throws {
        var generation = WebVTTThumbnailGeneration()
        let ownerA = generation.replaceOwner()
        let requestA = generation.replaceRequest()
        XCTAssertTrue(generation.isCurrent(owner: ownerA, request: requestA.request))

        let ownerB = generation.replaceOwner()
        XCTAssertFalse(generation.isCurrent(owner: ownerA))
        XCTAssertFalse(generation.isCurrent(owner: requestA.owner, request: requestA.request))
        let requestB = generation.replaceRequest()
        XCTAssertTrue(generation.isCurrent(owner: ownerB, request: requestB.request))

        let mediaURL = try XCTUnwrap(URL(string: "https://fixtures.invalid/video.m3u8"))
        let thumbnailURL = try XCTUnwrap(URL(string: "https://fixtures.invalid/thumbs.vtt?token=redacted"))
        let item = PlayerItem(
            title: "Fixture",
            url: mediaURL,
            thumbnailVTTURL: thumbnailURL,
            lastPosition: 12
        )
        let copy = PlayerManager.shared.makePlayerItemCopy(from: item, resumePosition: 42)

        XCTAssertEqual(copy.thumbnailVTTURL, thumbnailURL)
        XCTAssertEqual(copy.lastPosition, 42)

        let withoutThumbnails = PlayerItem(title: "Fixture", url: mediaURL, lastPosition: 12)
        XCTAssertNotEqual(
            PlayerView.LoadMode.single(item).identity,
            PlayerView.LoadMode.single(withoutThumbnails).identity
        )
    }

    func testSpriteTokenRejectsSameURLXToYToXABA() {
        var generation = WebVTTThumbnailGeneration()
        let firstX = generation.replaceSprite()
        let y = generation.replaceSprite()
        let secondX = generation.replaceSprite()

        XCTAssertFalse(firstX.sprite === y.sprite)
        XCTAssertFalse(y.sprite === secondX.sprite)
        XCTAssertFalse(generation.isCurrent(owner: firstX.owner, sprite: firstX.sprite))
        XCTAssertFalse(generation.isCurrent(owner: y.owner, sprite: y.sprite))
        XCTAssertTrue(generation.isCurrent(owner: secondX.owner, sprite: secondX.sprite))
    }

    func testLatestWorkSlotKeepsAAndCWhileReleasingDisplacedB() {
        var slot = LatestThumbnailWorkSlot<ThumbnailWorkPayload>()
        let a = ThumbnailWorkPayload()
        slot.replace(with: a)
        let active = slot.take()

        weak var displaced: ThumbnailWorkPayload?
        do {
            let b = ThumbnailWorkPayload()
            displaced = b
            slot.replace(with: b)
        }
        let c = ThumbnailWorkPayload()
        slot.replace(with: c)

        XCTAssertTrue(active === a)
        XCTAssertNil(displaced)
        XCTAssertTrue(slot.take() === c)
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let bytes = Data(repeating: 0xff, count: width * height * 4)
        let provider = try XCTUnwrap(CGDataProvider(data: bytes as CFData))
        return try XCTUnwrap(
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        )
    }

    private func makeOrientedTIFF() throws -> Data {
        let image = try makeImage(width: 2, height: 1)
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(data, "public.tiff" as CFString, 1, nil)
        )
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImagePropertyOrientation: 6] as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private final class ThumbnailTransportURLProtocol: URLProtocol {
    static let started = Notification.Name("PlayerKitTests.ThumbnailTransport.started")
    static let stopped = Notification.Name("PlayerKitTests.ThumbnailTransport.stopped")

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        if url.path == "/cancel" {
            NotificationCenter.default.post(name: Self.started, object: nil, userInfo: ["url": url])
            return
        }
        if url.path == "/no-response" {
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let status = url.path == "/status" ? 503 : 200
        let length = url.path == "/length" ? "5" : (url.path == "/overflow" ? nil : "4")
        let headers = length.map { ["Content-Length": $0] } ?? [:]
        let responseURL = url.path == "/final-url"
            ? URL(string: "https://cdn.invalid/thumbs/final.vtt")!
            : url
        guard let response = HTTPURLResponse(
            url: responseURL,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if url.path == "/success" || url.path == "/final-url" {
            client?.urlProtocol(self, didLoad: Data([0, 1]))
            client?.urlProtocol(self, didLoad: Data([2, 3]))
        } else if url.path == "/overflow" {
            client?.urlProtocol(self, didLoad: Data([0, 1, 2, 3]))
            client?.urlProtocol(self, didLoad: Data([4]))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        guard let url = request.url, url.path == "/cancel" else { return }
        NotificationCenter.default.post(name: Self.stopped, object: nil, userInfo: ["url": url])
    }
}

private final class ThumbnailWorkPayload {}
