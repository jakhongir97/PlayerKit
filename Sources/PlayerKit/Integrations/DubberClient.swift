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

    struct UpdatePayload: Decodable, Sendable {
        let status: String?
        let progress: String?
        let segments_ready: Int?
        let total_segments: Int?
        let error: String?
    }

    struct WarningPayload: Decodable, Sendable {
        let message: String?
    }

    struct DonePayload: Decodable, Sendable {
        let status: String?
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

        let sessionID = try JSONDecoder().decode(StartResponse.self, from: data).session_id
        debugLog("Dub session started. session_id=\(sessionID)")
        return sessionID
    }

    func masterPlaylistURL(sessionID: String, configuration: DubberConfiguration) -> URL {
        configuration.baseURL
            .appendingPathComponent(sessionID)
            .appendingPathComponent("master.m3u8")
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
            case "update":
                guard let payload = try? decoder.decode(UpdatePayload.self, from: payloadData) else {
                    return []
                }
                return [.update(payload)]
            case "warning":
                guard let payload = try? decoder.decode(WarningPayload.self, from: payloadData) else {
                    return []
                }
                return [.warning(payload)]
            case "done":
                guard let payload = try? decoder.decode(DonePayload.self, from: payloadData) else {
                    return []
                }
                return [.done(payload)]
            default:
                return []
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
    }

    private func debugLog(_ message: String) {
        print("[PlayerKit][DubberClient] \(message)")
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
