import Foundation

struct DubberClient {
    private struct StartRequest: Encodable {
        let video_url: String
        let language: String
        let translate_from: String
    }

    private struct StartResponse: Decodable {
        let sessionID: String

        private enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case sessionId
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let snakeCase = try container.decodeIfPresent(String.self, forKey: .sessionID),
               !snakeCase.isEmpty {
                sessionID = snakeCase
                return
            }

            if let camelCase = try container.decodeIfPresent(String.self, forKey: .sessionId),
               !camelCase.isEmpty {
                sessionID = camelCase
                return
            }

            throw DecodingError.keyNotFound(
                CodingKeys.sessionID,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Missing dub session identifier."
                )
            )
        }
    }

    struct UpdatePayload: Decodable, Sendable {
        let status: String?
        let progress: String?
        let segments_ready: Int?
        let total_segments: Int?
        let error: String?

        var hasKnownFields: Bool {
            status != nil
                || progress != nil
                || segments_ready != nil
                || total_segments != nil
                || error != nil
        }

        private enum CodingKeys: String, CodingKey {
            case status
            case progress
            case segments_ready
            case total_segments
            case segmentsReady
            case totalSegments
            case error
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decodeIfPresent(String.self, forKey: .status)
            progress = try container.decodeIfPresent(String.self, forKey: .progress)

            let snakeSegmentsReady = try container.decodeIfPresent(Int.self, forKey: .segments_ready)
            let camelSegmentsReady = try container.decodeIfPresent(Int.self, forKey: .segmentsReady)
            segments_ready = snakeSegmentsReady ?? camelSegmentsReady

            let snakeTotalSegments = try container.decodeIfPresent(Int.self, forKey: .total_segments)
            let camelTotalSegments = try container.decodeIfPresent(Int.self, forKey: .totalSegments)
            total_segments = snakeTotalSegments ?? camelTotalSegments

            error = try container.decodeIfPresent(String.self, forKey: .error)
        }
    }

    struct WarningPayload: Decodable, Sendable {
        let message: String?

        var hasKnownFields: Bool {
            message != nil
        }
    }

    struct DonePayload: Decodable, Sendable {
        let status: String?

        var hasKnownFields: Bool {
            status != nil
        }

        private enum CodingKeys: String, CodingKey {
            case status
            case state
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decodeIfPresent(String.self, forKey: .status)
                ?? (try container.decodeIfPresent(String.self, forKey: .state))
        }
    }

    struct PollChunk: Decodable, Sendable {
        let index: Int?
        let startTime: Double?
        let endTime: Double?
        let audioDuration: Double?
        let audioBase64: String?
        let speaker: String?
        let text: String?

        var hasEmbeddedAudio: Bool {
            guard let audioBase64 else { return false }
            return !audioBase64.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        private enum CodingKeys: String, CodingKey {
            case index
            case startTime = "start_time"
            case endTime = "end_time"
            case audioDuration = "audio_duration"
            case audioBase64 = "audio_base64"
            case speaker
            case text
        }
    }

    struct PollResponse: Decodable, Sendable {
        let status: String?
        let playable: Bool
        let segmentsReady: Int
        let totalSegments: Int
        let error: String?
        let chunks: [PollChunk]

        private enum CodingKeys: String, CodingKey {
            case status
            case playable
            case isPlayable
            case is_playable
            case segmentsReady = "segments_ready"
            case totalSegments = "total_segments"
            case segmentsReadyCamel = "segmentsReady"
            case totalSegmentsCamel = "totalSegments"
            case error
            case chunks
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decodeIfPresent(String.self, forKey: .status)
            playable = try Self.decodePlayable(from: container)
            let snakeSegmentsReady = try container.decodeIfPresent(Int.self, forKey: .segmentsReady)
            let camelSegmentsReady = try container.decodeIfPresent(Int.self, forKey: .segmentsReadyCamel)
            let snakeTotalSegments = try container.decodeIfPresent(Int.self, forKey: .totalSegments)
            let camelTotalSegments = try container.decodeIfPresent(Int.self, forKey: .totalSegmentsCamel)
            segmentsReady = max(snakeSegmentsReady ?? camelSegmentsReady ?? 0, 0)
            totalSegments = max(snakeTotalSegments ?? camelTotalSegments ?? 0, 0)
            error = try container.decodeIfPresent(String.self, forKey: .error)
            chunks = try container.decodeIfPresent([PollChunk].self, forKey: .chunks) ?? []
        }

        private static func decodePlayable(
            from container: KeyedDecodingContainer<CodingKeys>
        ) throws -> Bool {
            let playableKeys: [CodingKeys] = [.playable, .isPlayable, .is_playable]

            for key in playableKeys {
                if let value = try container.decodeIfPresent(Bool.self, forKey: key) {
                    return value
                }

                if let value = try container.decodeIfPresent(Int.self, forKey: key) {
                    return value != 0
                }

                if let value = try container.decodeIfPresent(String.self, forKey: key) {
                    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                    case "1", "true", "yes", "ready", "playable":
                        return true
                    case "0", "false", "no":
                        return false
                    default:
                        continue
                    }
                }
            }

            return false
        }
    }

    struct DubAudioReadiness: Sendable, Equatable {
        let verifiedWindowStart: Double
        let verifiedWindowEnd: Double
        let probedSegmentURLs: [URL]
    }

    private struct PlaylistSegment: Sendable {
        let url: URL
        let startTime: Double
        let endTime: Double
    }

    private enum ProbeError: Error {
        case dubbedAudioPlaylistMissing
        case dubbedAudioSegmentsMissing
        case dubbedAudioWindowUnavailable
        case dubbedAudioSegmentUnavailable(URL)
    }

    enum SessionEvent: Sendable {
        case update(UpdatePayload)
        case warning(WarningPayload)
        case done(DonePayload)
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
        let requestStart = Date()
        debugLog(
            "Sending dub start request. language=\(payload.language) " +
            "translate_from=\(payload.translate_from)"
        )

        let (data, response) = try await session.data(for: request)
        let requestElapsed = Date().timeIntervalSince(requestStart)
        if let httpResponse = response as? HTTPURLResponse {
            debugLog(
                "Dub start response. status=\(httpResponse.statusCode) " +
                "elapsed=\(debugInterval(requestElapsed)) body_bytes=\(data.count)"
            )
        } else {
            debugLog("Dub start response received with non-HTTP payload. elapsed=\(debugInterval(requestElapsed))")
        }
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ... 299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            debugLog("Start session failed. status=\(httpResponse.statusCode) body=\(body)")
            throw PlayerKitError.dubberRequestFailed("HTTP \(httpResponse.statusCode)")
        }

        let sessionID = try JSONDecoder().decode(StartResponse.self, from: data).sessionID
        debugLog("Dub session started. session_id=\(sessionID)")
        return sessionID
    }

    func masterPlaylistURL(sessionID: String, configuration: DubberConfiguration) -> URL {
        configuration.baseURL
            .appendingPathComponent(sessionID)
            .appendingPathComponent("master.m3u8")
    }

    func pollURL(
        sessionID: String,
        configuration: DubberConfiguration,
        after: Int = -1
    ) -> URL {
        let baseURL = configuration.baseURL
            .appendingPathComponent(sessionID)
            .appendingPathComponent("poll")

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }

        components.queryItems = [
            URLQueryItem(name: "after", value: String(after))
        ]

        return components.url ?? baseURL
    }

    func pollSession(
        sessionID: String,
        configuration: DubberConfiguration
    ) async throws -> PollResponse {
        let url = pollURL(
            sessionID: sessionID,
            configuration: configuration
        )

        let requestStart = Date()
        let (data, response) = try await session.data(from: url)
        let requestElapsed = Date().timeIntervalSince(requestStart)

        if let httpResponse = response as? HTTPURLResponse,
           !(200 ... 299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            debugLog(
                "Poll failed. session_id=\(sessionID) status=\(httpResponse.statusCode) " +
                "elapsed=\(debugInterval(requestElapsed)) body=\(body)"
            )
            throw PlayerKitError.dubberRequestFailed("HTTP \(httpResponse.statusCode)")
        }

        let poll = try JSONDecoder().decode(PollResponse.self, from: data)
        debugLog(
            "Poll response. session_id=\(sessionID) status=\(poll.status ?? "nil") " +
            "playable=\(poll.playable) " +
            "segments=\(poll.segmentsReady)/\(poll.totalSegments) " +
            "chunks=\(poll.chunks.count) elapsed=\(debugInterval(requestElapsed)) " +
            "error=\(poll.error ?? "nil")"
        )
        return poll
    }

    func probeDubAudioReadiness(
        sessionID: String,
        configuration: DubberConfiguration,
        targetLanguageCode: String,
        playbackTime: Double,
        headroom: Double = 8
    ) async throws -> DubAudioReadiness {
        let masterURL = masterPlaylistURL(sessionID: sessionID, configuration: configuration)
        let masterPlaylist = try await fetchText(from: masterURL)
        let audioPlaylistURL = try resolveDubAudioPlaylistURL(
            in: masterPlaylist,
            baseURL: masterURL,
            targetLanguageCode: targetLanguageCode
        )
        let audioPlaylist = try await fetchText(from: audioPlaylistURL)
        let segments = try parseAudioSegments(in: audioPlaylist, baseURL: audioPlaylistURL)
        let probeSegments = try segmentsToProbe(
            in: segments,
            playbackTime: max(playbackTime, 0),
            headroom: max(headroom, 2)
        )

        for segment in probeSegments {
            try await probeDubSegment(at: segment.url)
        }

        return DubAudioReadiness(
            verifiedWindowStart: probeSegments.first?.startTime ?? 0,
            verifiedWindowEnd: probeSegments.last?.endTime ?? 0,
            probedSegmentURLs: probeSegments.map(\.url)
        )
    }

    func streamSessionEvents(
        sessionID: String,
        configuration: DubberConfiguration,
        onEvent: @escaping @Sendable (SessionEvent) -> Void
    ) async throws {
        let eventsURL = configuration.baseURL
            .appendingPathComponent(sessionID)
            .appendingPathComponent("events")

        var request = URLRequest(url: eventsURL)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = max(configuration.eventStreamRequestTimeout, 30)
        let streamStart = Date()
        debugLog(
            "Opening SSE stream. session_id=\(sessionID) " +
            "url=\(eventsURL.absoluteString) timeout=\(debugInterval(request.timeoutInterval))"
        )

        if #available(iOS 15.0, macOS 12.0, *) {
            do {
                let (bytes, response) = try await session.bytes(for: request)
                let headerElapsed = Date().timeIntervalSince(streamStart)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw PlayerKitError.dubberRequestFailed("Invalid response")
                }
                guard (200 ... 299).contains(httpResponse.statusCode) else {
                    throw PlayerKitError.dubberRequestFailed("HTTP \(httpResponse.statusCode)")
                }

                let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "nil"
                let cacheControl = httpResponse.value(forHTTPHeaderField: "Cache-Control") ?? "nil"
                let transferEncoding = httpResponse.value(forHTTPHeaderField: "Transfer-Encoding") ?? "nil"
                let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "nil"
                let requestID =
                    httpResponse.value(forHTTPHeaderField: "x-request-id")
                    ?? httpResponse.value(forHTTPHeaderField: "x-amzn-requestid")
                    ?? httpResponse.value(forHTTPHeaderField: "cf-ray")
                    ?? "nil"
                debugLog(
                    "SSE connected. session_id=\(sessionID) status=\(httpResponse.statusCode) " +
                    "elapsed=\(debugInterval(headerElapsed))"
                )
                debugLog(
                    "SSE headers. session_id=\(sessionID) content_type=\(contentType) " +
                    "cache_control=\(cacheControl) transfer_encoding=\(transferEncoding) " +
                    "content_length=\(contentLength) request_id=\(requestID)"
                )
                var parser = SSEParser()
                var lineCount = 0
                var eventCount = 0
                var firstEventAt: Date?
                var closedByCancellation = false

                for try await rawLine in bytes.lines {
                    if Task.isCancelled {
                        closedByCancellation = true
                        break
                    }

                    lineCount += 1
                    if lineCount <= 5 {
                        debugLog(
                            "SSE raw line[\(lineCount)]. session_id=\(sessionID) " +
                            "value=\(truncatedDebugLine(String(rawLine)))"
                        )
                    }

                    let events = parser.ingestLine(String(rawLine))
                    for event in events {
                        eventCount += 1
                        debugLog("SSE parsed event. session_id=\(sessionID) kind=\(debugEventKind(event))")
                        if firstEventAt == nil {
                            let now = Date()
                            firstEventAt = now
                            let elapsedToFirstEvent = now.timeIntervalSince(streamStart)
                            debugLog(
                                "First SSE event parsed. session_id=\(sessionID) " +
                                "elapsed=\(debugInterval(elapsedToFirstEvent))"
                            )
                        }
                        onEvent(event)
                    }
                }

                let trailingEvents = parser.flush()
                for event in trailingEvents {
                    eventCount += 1
                    debugLog("SSE parsed trailing event. session_id=\(sessionID) kind=\(debugEventKind(event))")
                    onEvent(event)
                }

                let totalElapsed = Date().timeIntervalSince(streamStart)
                let closeReason = closedByCancellation ? "cancelled" : "eof"
                debugLog(
                    "SSE closed. session_id=\(sessionID) reason=\(closeReason) " +
                    "lines=\(lineCount) events=\(eventCount) elapsed=\(debugInterval(totalElapsed))"
                )
                if lineCount == 0 {
                    debugLog("SSE closed with no lines. session_id=\(sessionID)")
                }
                if eventCount == 0 {
                    debugLog("SSE closed with no parsed events. session_id=\(sessionID)")
                }
                return
            } catch {
                let nsError = error as NSError
                let totalElapsed = Date().timeIntervalSince(streamStart)
                debugLog(
                    "SSE stream failed. session_id=\(sessionID) " +
                    "domain=\(nsError.domain) code=\(nsError.code) " +
                    "description=\(nsError.localizedDescription) " +
                    "elapsed=\(debugInterval(totalElapsed))"
                )
                throw error
            }
        }

        throw PlayerKitError.dubberRequestFailed("SSE requires iOS 15+ / macOS 12+")
    }

    private struct SSEParser {
        private var eventName = "message"
        private var dataLines: [String] = []

        mutating func ingestLine(_ rawLine: String) -> [SessionEvent] {
            let line = rawLine.hasSuffix("\r")
                ? String(rawLine.dropLast())
                : rawLine

            if line.isEmpty {
                return emitEventIfReady()
            }

            if line.hasPrefix(":") {
                return []
            }

            if line.hasPrefix("event:") {
                // Some backends omit the blank separator between events.
                // If a new `event:` arrives while we already have data, treat it as event boundary.
                var emitted: [SessionEvent] = []
                if !dataLines.isEmpty {
                    emitted = emitEventIfReady()
                }
                eventName = parseFieldValue(line, prefix: "event:")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return emitted
            }

            if line.hasPrefix("data:") {
                dataLines.append(parseFieldValue(line, prefix: "data:"))
            }

            return []
        }

        mutating func flush() -> [SessionEvent] {
            emitEventIfReady()
        }

        private mutating func emitEventIfReady() -> [SessionEvent] {
            guard !dataLines.isEmpty else {
                resetEvent()
                return []
            }

            let rawData = dataLines.joined(separator: "\n")
            defer { resetEvent() }

            guard let payloadData = rawData.data(using: .utf8) else {
                return []
            }

            let decoder = JSONDecoder()
            let normalizedEvent = eventName.lowercased()

            switch normalizedEvent {
            case "update", "progress", "status":
                guard let payload = try? decoder.decode(UpdatePayload.self, from: payloadData) else {
                    return []
                }
                guard payload.hasKnownFields else {
                    return []
                }
                return [.update(payload)]
            case "warning", "warn":
                guard let payload = try? decoder.decode(WarningPayload.self, from: payloadData) else {
                    return []
                }
                guard payload.hasKnownFields else {
                    return []
                }
                return [.warning(payload)]
            case "done", "complete", "completed":
                guard let payload = try? decoder.decode(DonePayload.self, from: payloadData) else {
                    return []
                }
                guard payload.hasKnownFields else {
                    return []
                }
                return [.done(payload)]
            default:
                return inferEvent(from: payloadData, decoder: decoder)
            }
        }

        private mutating func resetEvent() {
            eventName = "message"
            dataLines.removeAll(keepingCapacity: true)
        }

        private func parseFieldValue(_ line: String, prefix: String) -> String {
            var value = String(line.dropFirst(prefix.count))
            if value.first == " " {
                value.removeFirst()
            }
            return value
        }

        private func inferEvent(from payloadData: Data, decoder: JSONDecoder) -> [SessionEvent] {
            if let update = try? decoder.decode(UpdatePayload.self, from: payloadData),
               update.hasKnownFields {
                return [.update(update)]
            }

            if let warning = try? decoder.decode(WarningPayload.self, from: payloadData),
               warning.hasKnownFields {
                return [.warning(warning)]
            }

            if let done = try? decoder.decode(DonePayload.self, from: payloadData),
               done.hasKnownFields {
                return [.done(done)]
            }

            return []
        }
    }

    private func debugLog(_ message: String) {
        print("[PlayerKit][DubberClient] \(message)")
    }

    private func fetchText(from url: URL) async throws -> String {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode) else {
            throw ProbeError.dubbedAudioPlaylistMissing
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func resolveDubAudioPlaylistURL(
        in masterPlaylist: String,
        baseURL: URL,
        targetLanguageCode: String
    ) throws -> URL {
        let lines = masterPlaylist
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        let normalizedLanguage = targetLanguageCode.lowercased()
        for line in lines where line.hasPrefix("#EXT-X-MEDIA:") && line.contains("TYPE=AUDIO") {
            let language = attributeValue(named: "LANGUAGE", in: line)?.lowercased()
            let uri = attributeValue(named: "URI", in: line)
            if let uri, language?.hasPrefix(normalizedLanguage) == true {
                guard let resolvedURL = URL(string: uri, relativeTo: baseURL)?.absoluteURL else {
                    break
                }
                return resolvedURL
            }
        }

        if let fallbackLine = lines.first(where: { !$0.hasPrefix("#") && $0.localizedCaseInsensitiveContains("dub-audio") }),
           let resolvedURL = URL(string: fallbackLine, relativeTo: baseURL)?.absoluteURL {
            return resolvedURL
        }

        if let fallbackURI = lines
            .filter({ $0.hasPrefix("#EXT-X-MEDIA:") && $0.contains("TYPE=AUDIO") })
            .compactMap({ attributeValue(named: "URI", in: $0) })
            .first(where: { $0.localizedCaseInsensitiveContains("dub-audio") }),
           let resolvedURL = URL(string: fallbackURI, relativeTo: baseURL)?.absoluteURL {
            return resolvedURL
        }

        throw ProbeError.dubbedAudioPlaylistMissing
    }

    private func parseAudioSegments(
        in playlist: String,
        baseURL: URL
    ) throws -> [PlaylistSegment] {
        let lines = playlist
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        var pendingDuration: Double?
        var currentStartTime = 0.0
        var segments: [PlaylistSegment] = []

        for line in lines {
            if line.hasPrefix("#EXTINF:") {
                let rawValue = line
                    .dropFirst("#EXTINF:".count)
                    .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                    .first
                pendingDuration = rawValue.flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                continue
            }

            guard !line.isEmpty, !line.hasPrefix("#"), let duration = pendingDuration else {
                continue
            }

            guard let segmentURL = URL(string: line, relativeTo: baseURL)?.absoluteURL else {
                pendingDuration = nil
                continue
            }

            let endTime = currentStartTime + max(duration, 0)
            segments.append(
                PlaylistSegment(
                    url: segmentURL,
                    startTime: currentStartTime,
                    endTime: endTime
                )
            )
            currentStartTime = endTime
            pendingDuration = nil
        }

        guard !segments.isEmpty else {
            throw ProbeError.dubbedAudioSegmentsMissing
        }
        return segments
    }

    private func segmentsToProbe(
        in segments: [PlaylistSegment],
        playbackTime: Double,
        headroom: Double
    ) throws -> [PlaylistSegment] {
        let verificationEnd = playbackTime + headroom
        let overlappingSegments = segments.filter { segment in
            segment.endTime > playbackTime && segment.startTime < verificationEnd
        }

        if !overlappingSegments.isEmpty {
            return Array(overlappingSegments.prefix(3))
        }

        if let firstUpcoming = segments.first(where: { $0.endTime > playbackTime }) {
            return [firstUpcoming]
        }

        throw ProbeError.dubbedAudioWindowUnavailable
    }

    private func probeDubSegment(at url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.dubbedAudioSegmentUnavailable(url)
        }

        switch httpResponse.statusCode {
        case 200, 206:
            return
        default:
            throw ProbeError.dubbedAudioSegmentUnavailable(url)
        }
    }

    private func attributeValue(named name: String, in line: String) -> String? {
        let pattern = "\(name)=\""
        guard let range = line.range(of: pattern) else { return nil }
        let valueStart = range.upperBound
        guard let valueEnd = line[valueStart...].firstIndex(of: "\"") else { return nil }
        return String(line[valueStart..<valueEnd])
    }

    private func debugInterval(_ seconds: TimeInterval) -> String {
        String(format: "%.1fs", seconds)
    }

    private func truncatedDebugLine(_ line: String) -> String {
        let sanitized = line.replacingOccurrences(of: "\r", with: "\\r")
        let limit = 220
        if sanitized.count <= limit {
            return sanitized
        }
        let endIndex = sanitized.index(sanitized.startIndex, offsetBy: limit)
        return String(sanitized[..<endIndex]) + "..."
    }

    private func debugEventKind(_ event: SessionEvent) -> String {
        switch event {
        case .update:
            return "update"
        case .warning:
            return "warning"
        case .done:
            return "done"
        }
    }
}
