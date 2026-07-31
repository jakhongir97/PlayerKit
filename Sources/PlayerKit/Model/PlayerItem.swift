import SwiftUI

public struct PlayerItem {
    public let title: String
    public let description: String?
    public let url: URL
    public let posterUrl: URL?
    public let castVideoUrl: URL?
    public let externalPlaybackURL: URL?
    public let externalPlaybackContentType: String?
    public let externalPlaybackDuration: Double?
    public var lastPosition: Double? // Optional last playback position
    public let episodeIndex: Int?

    #if os(macOS)
    /// A non-secret, app-owned opaque identifier used only to derive the
    /// diagnostics fingerprint. Never pass signed URLs, headers, or tokens.
    public let playbackHealthAssetIdentifier: String?
    /// Set by the app only for remote, clear HLS movie or episode playback.
    public let playbackHealthMonitoringEligible: Bool
    #endif

    // Add a public initializer
    #if os(macOS)
    public init(title: String,
                description: String? = nil,
                url: URL,
                posterUrl: URL? = nil,
                castVideoUrl: URL? = nil,
                externalPlaybackURL: URL? = nil,
                externalPlaybackContentType: String? = nil,
                externalPlaybackDuration: Double? = nil,
                lastPosition: Double? = nil,
                episodeIndex: Int? = nil,
                playbackHealthAssetIdentifier: String? = nil,
                playbackHealthMonitoringEligible: Bool = false) {
        self.title = title
        self.description = description
        self.url = url
        self.posterUrl = posterUrl
        self.castVideoUrl = castVideoUrl ?? externalPlaybackURL
        self.externalPlaybackURL = externalPlaybackURL ?? castVideoUrl
        self.externalPlaybackContentType = externalPlaybackContentType
        self.externalPlaybackDuration = externalPlaybackDuration
        self.lastPosition = lastPosition
        self.episodeIndex = episodeIndex
        self.playbackHealthAssetIdentifier = playbackHealthAssetIdentifier
        self.playbackHealthMonitoringEligible = playbackHealthMonitoringEligible
    }
    #else
    public init(title: String,
                description: String? = nil,
                url: URL,
                posterUrl: URL? = nil,
                castVideoUrl: URL? = nil,
                externalPlaybackURL: URL? = nil,
                externalPlaybackContentType: String? = nil,
                externalPlaybackDuration: Double? = nil,
                lastPosition: Double? = nil,
                episodeIndex: Int? = nil) {
        self.title = title
        self.description = description
        self.url = url
        self.posterUrl = posterUrl
        self.castVideoUrl = castVideoUrl ?? externalPlaybackURL
        self.externalPlaybackURL = externalPlaybackURL ?? castVideoUrl
        self.externalPlaybackContentType = externalPlaybackContentType
        self.externalPlaybackDuration = externalPlaybackDuration
        self.lastPosition = lastPosition
        self.episodeIndex = episodeIndex
    }
    #endif
}

extension PlayerItem {

    var preferredExternalPlaybackURL: URL? {
        externalPlaybackURL ?? castVideoUrl ?? (!url.isFileURL ? url : nil)
    }

    var preferredExternalPlaybackContentType: String {
        if let externalPlaybackContentType,
           !externalPlaybackContentType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return externalPlaybackContentType
        }

        guard let resolvedURL = preferredExternalPlaybackURL else {
            return "video/mp4"
        }

        switch resolvedURL.pathExtension.lowercased() {
        case "m3u8":
            return "application/x-mpegURL"
        case "mpd":
            return "application/dash+xml"
        case "mov":
            return "video/quicktime"
        case "m4v", "mp4":
            return "video/mp4"
        default:
            return "video/mp4"
        }
    }
}

public enum PlayerContentType {
    case movie
    case episode
}
