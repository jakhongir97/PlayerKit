import XCTest
@testable import PlayerKit

final class DubberClientTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testStartSessionIncludesRequiredTitleInRequestBody() async throws {
        let requestExpectation = expectation(description: "start request received")

        StubURLProtocol.requestHandler = { request in
            defer { requestExpectation.fulfill() }

            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://dubbing.uz/api/instant-dub/start")

            let bodyData = try XCTUnwrap(self.requestBody(from: request))
            let payload = try XCTUnwrap(
                JSONSerialization.jsonObject(with: bodyData) as? [String: String]
            )

            XCTAssertEqual(payload["video_url"], "https://cdn.example.com/master.m3u8")
            XCTAssertEqual(payload["title"], "Breaking Bad - Pilot - Season 1, Episode 1")
            XCTAssertEqual(payload["language"], "uz")
            XCTAssertEqual(payload["translate_from"], "auto")

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = Data(#"{"session_id":"session-123"}"#.utf8)
            return (response, data)
        }

        let client = DubberClient(session: makeStubSession())
        let sessionID = try await client.startSession(
            sourceURL: URL(string: "https://cdn.example.com/master.m3u8")!,
            title: "Breaking Bad - Pilot - Season 1, Episode 1",
            configuration: DubberConfiguration(),
            language: nil,
            translateFrom: nil
        )

        await fulfillment(of: [requestExpectation], timeout: 1.0)
        XCTAssertEqual(sessionID, "session-123")
    }

    private func makeStubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func requestBody(from request: URLRequest) throws -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            if bytesRead < 0 {
                throw stream.streamError ?? URLError(.cannotParseResponse)
            }
            if bytesRead == 0 {
                break
            }
            data.append(contentsOf: buffer.prefix(bytesRead))
        }

        return data
    }
}

private final class StubURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
