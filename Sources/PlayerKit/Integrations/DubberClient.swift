import Foundation

struct DubberClient {
    private struct StartRequest: Encodable {
        let video_url: String
        let language: String
        let translate_from: String
    }

    private struct StartResponse: Decodable {
        let session_id: String
    }

    struct PollResponse: Decodable {
        let status: String
        let segments_ready: Int
        let total_segments: Int
        let error: String?
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func startSession(
        sourceURL: URL,
        configuration: DubberConfiguration,
        language: String?,
        translateFrom: String?
    ) async throws -> String {
        debugLog("Starting dub session. source=\(sourceURL.debugDescription) base=\(configuration.baseURL.debugDescription)")
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("start"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = StartRequest(
            video_url: sourceURL.absoluteString,
            language: language ?? configuration.defaultLanguage,
            translate_from: translateFrom ?? configuration.defaultTranslateFrom
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ... 299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            debugLog("Start session failed. status=\(httpResponse.statusCode) body=\(body)")
            throw PlayerKitError.dubberRequestFailed("HTTP \(httpResponse.statusCode)")
        }

        let sessionID = try JSONDecoder().decode(StartResponse.self, from: data).session_id
        debugLog("Dub session started. session_id=\(sessionID)")
        return sessionID
    }

    func masterPlaylistURL(sessionID: String, configuration: DubberConfiguration) -> URL {
        configuration.baseURL
            .appendingPathComponent(sessionID)
            .appendingPathComponent("master.m3u8")
    }

    func pollSession(
        sessionID: String,
        configuration: DubberConfiguration
    ) async throws -> PollResponse {
        let url = configuration.baseURL
            .appendingPathComponent(sessionID)
            .appendingPathComponent("poll")
        let (data, response) = try await session.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ... 299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            debugLog("Poll failed. session_id=\(sessionID) status=\(httpResponse.statusCode) body=\(body)")
            throw PlayerKitError.dubberRequestFailed("HTTP \(httpResponse.statusCode)")
        }
        let poll = try JSONDecoder().decode(PollResponse.self, from: data)
        debugLog(
            "Poll response. session_id=\(sessionID) status=\(poll.status) " +
            "segments=\(poll.segments_ready)/\(poll.total_segments) error=\(poll.error ?? "nil")"
        )
        return poll
    }

    private func debugLog(_ message: String) {
        print("[PlayerKit][DubberClient] \(message)")
    }
}
