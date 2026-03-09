#if os(macOS)
import Darwin
import Foundation

struct DLNADeviceDiscoveryService {
    func discoverDevices(timeout: TimeInterval = 2.5) async -> [ExternalPlaybackDevice] {
        let responses = await Task.detached(priority: .utility) {
            SSDPResponse.discoverMediaRenderers(timeout: timeout)
        }.value

        guard !responses.isEmpty else {
            return []
        }

        return await withTaskGroup(of: ExternalPlaybackDevice?.self, returning: [ExternalPlaybackDevice].self) { group in
            for response in responses {
                group.addTask {
                    await resolveDevice(from: response)
                }
            }

            var devices: [ExternalPlaybackDevice] = []
            for await device in group {
                if let device {
                    devices.append(device)
                }
            }

            return devices.sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private func resolveDevice(from response: SSDPResponse) async -> ExternalPlaybackDevice? {
        guard let locationURL = response.locationURL else {
            return nil
        }

        let request = URLRequest(url: locationURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let xml = String(data: data, encoding: .utf8) else {
                return nil
            }

            guard let controlURL = xml.avTransportControlURL(baseURL: locationURL) else {
                return nil
            }

            let friendlyName = xml.firstXMLValue(forTag: "friendlyName")
                ?? response.server
                ?? locationURL.host
                ?? "DLNA Renderer"

            return ExternalPlaybackDevice(
                id: response.usn ?? controlURL.absoluteString,
                name: friendlyName,
                kind: .dlna,
                locationURL: locationURL,
                avTransportControlURL: controlURL
            )
        } catch {
            return nil
        }
    }
}

struct DLNAPlaybackController {
    func play(item: PlayerItem, on device: ExternalPlaybackDevice) async throws {
        guard let controlURL = device.avTransportControlURL else {
            throw PlayerKitError.externalPlaybackDeviceUnavailable
        }

        let source = try makeSource(from: item)
        _ = try? await sendCommand(name: "Stop", innerXML:
            """
            <u:Stop xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
            <InstanceID>0</InstanceID>
            </u:Stop>
            """,
            controlURL: controlURL,
            timeout: 2
        )

        _ = try await sendCommand(name: "SetAVTransportURI", innerXML:
            """
            <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
            <InstanceID>0</InstanceID>
            <CurrentURI>\(source.url.absoluteString.xmlEscaped)</CurrentURI>
            <CurrentURIMetaData>\(source.didlLiteMetadata.xmlEscaped)</CurrentURIMetaData>
            </u:SetAVTransportURI>
            """,
            controlURL: controlURL,
            timeout: 4
        )

        do {
            _ = try await sendCommand(name: "Play", innerXML:
                """
                <u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
                <InstanceID>0</InstanceID>
                <Speed>1</Speed>
                </u:Play>
                """,
                controlURL: controlURL,
                timeout: 4
            )
        } catch {
            let state = try? await transportState(on: device)
            if state != "PLAYING" && state != "TRANSITIONING" {
                throw error
            }
        }
    }

    func pause(on device: ExternalPlaybackDevice) async throws {
        guard let controlURL = device.avTransportControlURL else {
            throw PlayerKitError.externalPlaybackDeviceUnavailable
        }

        _ = try await sendCommand(name: "Pause", innerXML:
            """
            <u:Pause xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
            <InstanceID>0</InstanceID>
            </u:Pause>
            """,
            controlURL: controlURL,
            timeout: 3
        )
    }

    func stop(on device: ExternalPlaybackDevice) async throws {
        guard let controlURL = device.avTransportControlURL else {
            throw PlayerKitError.externalPlaybackDeviceUnavailable
        }

        _ = try await sendCommand(name: "Stop", innerXML:
            """
            <u:Stop xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
            <InstanceID>0</InstanceID>
            </u:Stop>
            """,
            controlURL: controlURL,
            timeout: 3
        )
    }

    private func transportState(on device: ExternalPlaybackDevice) async throws -> String? {
        guard let controlURL = device.avTransportControlURL else {
            throw PlayerKitError.externalPlaybackDeviceUnavailable
        }

        let response = try await sendCommand(name: "GetTransportInfo", innerXML:
            """
            <u:GetTransportInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
            <InstanceID>0</InstanceID>
            </u:GetTransportInfo>
            """,
            controlURL: controlURL,
            timeout: 3
        )
        return response.firstXMLValue(forTag: "CurrentTransportState")
    }

    private func sendCommand(
        name: String,
        innerXML: String,
        controlURL: URL,
        timeout: TimeInterval
    ) async throws -> String {
        let body =
            """
            <?xml version="1.0" encoding="utf-8"?>
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
            <s:Body>\(innerXML)</s:Body>
            </s:Envelope>
            """

        var request = URLRequest(url: controlURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(DLNAPlaybackController.serviceNamespace)#\(name)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw PlayerKitError.externalPlaybackFailed("DLNA command \(name) failed.")
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    private func makeSource(from item: PlayerItem) throws -> DLNAPlaybackSource {
        guard let url = item.preferredExternalPlaybackURL else {
            throw PlayerKitError.externalPlaybackURLMissing
        }

        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw PlayerKitError.externalPlaybackRequiresReachableURL
        }

        let contentType = item.externalPlaybackContentType ?? url.inferredDLNAContentType
        let didlClass = DLNAPlaybackSource.className(for: contentType)
        let durationText: String?
        if let externalPlaybackDuration = item.externalPlaybackDuration,
           externalPlaybackDuration.isFinite,
           externalPlaybackDuration > 0 {
            durationText = DLNAPlaybackSource.durationString(from: externalPlaybackDuration)
        } else {
            durationText = nil
        }

        return DLNAPlaybackSource(
            url: url,
            title: item.title.isEmpty ? "PlayerKit Stream" : item.title,
            subtitle: item.description,
            contentType: contentType,
            didlClass: didlClass,
            durationText: durationText,
            artworkURL: item.posterUrl
        )
    }

    private static let serviceNamespace = "urn:schemas-upnp-org:service:AVTransport:1"
}

private struct SSDPResponse {
    let locationURL: URL?
    let server: String?
    let usn: String?

    static func discoverMediaRenderers(timeout: TimeInterval) -> [SSDPResponse] {
        let socketDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketDescriptor >= 0 else {
            return []
        }

        defer { close(socketDescriptor) }

        var receiveTimeout = timeval(tv_sec: 0, tv_usec: 250_000)
        withUnsafePointer(to: &receiveTimeout) { pointer in
            _ = setsockopt(
                socketDescriptor,
                SOL_SOCKET,
                SO_RCVTIMEO,
                pointer,
                socklen_t(MemoryLayout<timeval>.size)
            )
        }

        var bindAddress = sockaddr_in()
        bindAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddress.sin_family = sa_family_t(AF_INET)
        bindAddress.sin_port = 0
        bindAddress.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let bindResult = withUnsafePointer(to: &bindAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            return []
        }

        let searchPayload =
            """
            M-SEARCH * HTTP/1.1\r
            HOST: 239.255.255.250:1900\r
            MAN: "ssdp:discover"\r
            MX: 2\r
            ST: urn:schemas-upnp-org:device:MediaRenderer:1\r
            \r
            """

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = in_port_t(1900).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &destination.sin_addr)

        _ = searchPayload.withCString { message in
            withUnsafePointer(to: &destination) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(socketDescriptor, message, strlen(message), 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        let deadline = Date().addingTimeInterval(timeout)
        var discoveredByID: [String: SSDPResponse] = [:]

        while Date() < deadline {
            var buffer = [UInt8](repeating: 0, count: 8_192)
            var fromAddress = sockaddr_in()
            var fromLength = socklen_t(MemoryLayout<sockaddr_in>.size)

            let bytesRead = withUnsafeMutablePointer(to: &fromAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(socketDescriptor, &buffer, buffer.count, 0, $0, &fromLength)
                }
            }

            if bytesRead <= 0 {
                continue
            }

            let responseText = String(decoding: buffer.prefix(Int(bytesRead)), as: UTF8.self)
            guard let response = SSDPResponse(responseText: responseText) else {
                continue
            }

            let identifier = response.usn ?? response.locationURL?.absoluteString ?? UUID().uuidString
            discoveredByID[identifier] = response
        }

        return Array(discoveredByID.values)
    }

    init?(responseText: String) {
        var headers: [String: String] = [:]
        for line in responseText.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = trimmed.firstIndex(of: ":") else {
                continue
            }

            let key = trimmed[..<separator].lowercased()
            let value = trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        let locationValue = headers["location"] ?? headers["Location"]
        let locationURL = locationValue.flatMap(URL.init(string:))
        guard locationURL != nil else {
            return nil
        }

        self.locationURL = locationURL
        self.server = headers["server"] ?? headers["Server"]
        self.usn = headers["usn"] ?? headers["USN"]
    }
}

private struct DLNAPlaybackSource {
    let url: URL
    let title: String
    let subtitle: String?
    let contentType: String
    let didlClass: String
    let durationText: String?
    let artworkURL: URL?

    var didlLiteMetadata: String {
        let resAttributes = [
            durationText.map { " duration=\"\($0.xmlEscaped)\"" } ?? "",
            " protocolInfo=\"http-get:*:\(contentType.xmlEscaped):DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000\""
        ].joined()

        let descriptionNode = subtitle.map { "<dc:description>\($0.xmlEscaped)</dc:description>" } ?? ""
        let artworkNode = artworkURL.map { "<upnp:albumArtURI>\($0.absoluteString.xmlEscaped)</upnp:albumArtURI>" } ?? ""

        return
            """
            <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
            <item id="0" parentID="0" restricted="1">
            <dc:title>\(title.xmlEscaped)</dc:title>
            \(descriptionNode)
            \(artworkNode)
            <upnp:class>\(didlClass.xmlEscaped)</upnp:class>
            <res\(resAttributes)>\(url.absoluteString.xmlEscaped)</res>
            </item>
            </DIDL-Lite>
            """
    }

    static func className(for contentType: String) -> String {
        if contentType.hasPrefix("audio/") {
            return "object.item.audioItem.musicTrack"
        }
        if contentType.hasPrefix("image/") {
            return "object.item.imageItem.photo"
        }
        return "object.item.videoItem.movie"
    }

    static func durationString(from seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }
}

private extension String {
    var xmlEscaped: String {
        self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    func firstXMLValue(forTag tag: String) -> String? {
        let pattern = "<(?:\\w+:)?\(NSRegularExpression.escapedPattern(for: tag))>(.*?)</(?:\\w+:)?\(NSRegularExpression.escapedPattern(for: tag))>"
        return firstRegexCapture(pattern: pattern)
            .flatMap { value in
                value.removingPercentEncoding ?? value
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func avTransportControlURL(baseURL: URL) -> URL? {
        let servicePattern = "<(?:\\w+:)?service>(.*?)</(?:\\w+:)?service>"
        for block in regexCaptures(pattern: servicePattern) {
            guard block.firstXMLValue(forTag: "serviceType") == "urn:schemas-upnp-org:service:AVTransport:1" else {
                continue
            }

            guard let controlPath = block.firstXMLValue(forTag: "controlURL") else {
                continue
            }

            return URL(string: controlPath, relativeTo: baseURL)?.absoluteURL
        }

        return nil
    }

    func regexCaptures(pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let range = NSRange(startIndex..., in: self)
        return regex.matches(in: self, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: self) else {
                return nil
            }
            return String(self[range])
        }
    }

    func firstRegexCapture(pattern: String) -> String? {
        regexCaptures(pattern: pattern).first
    }
}

private extension URL {
    var inferredDLNAContentType: String {
        switch pathExtension.lowercased() {
        case "m3u8":
            return "application/vnd.apple.mpegurl"
        case "mp4", "m4v":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "mp3":
            return "audio/mpeg"
        case "m4a":
            return "audio/mp4"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "ts":
            return "video/mp2t"
        default:
            return "video/mp4"
        }
    }
}
#endif
