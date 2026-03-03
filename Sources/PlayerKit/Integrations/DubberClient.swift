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
            throw PlayerKitError.dubberRequestFailed("HTTP \(httpResponse.statusCode)")
        }

        return try JSONDecoder().decode(StartResponse.self, from: data).session_id
    }

    func masterPlaylistURL(sessionID: String, configuration: DubberConfiguration) -> URL {
        configuration.baseURL
            .appendingPathComponent(sessionID)
            .appendingPathComponent("master.m3u8")
    }
}
