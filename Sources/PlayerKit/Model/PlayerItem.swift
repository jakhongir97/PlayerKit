import SwiftUI

public struct PlayerSkipSegment: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case intro
        case credits
    }

    public let kind: Kind
    public let startTime: Double
    public let endTime: Double
    public let targetTime: Double

    public init?(
        kind: Kind,
        startTime: Double,
        endTime: Double,
        targetTime: Double? = nil
    ) {
        let resolvedTarget = targetTime ?? endTime
        guard startTime.isFinite,
              endTime.isFinite,
              resolvedTarget.isFinite,
              startTime >= 0,
              endTime > startTime,
              resolvedTarget > startTime else {
            return nil
        }

        self.kind = kind
        self.startTime = startTime
        self.endTime = endTime
        self.targetTime = resolvedTarget
    }

    public func contains(_ time: Double) -> Bool {
        time.isFinite && time >= startTime && time < endTime
    }
}

public struct PlayerItem {
    public let title: String
    /// A title treatment — the artwork that spells the title out — to show in
    /// place of `title`. The text title is still the fallback: it is what the
    /// controls render until the image loads, if it fails, and what VoiceOver
    /// reads.
    public let titleImageURL: URL?
    public let description: String?
    public let url: URL
    public let posterUrl: URL?
    public let castVideoUrl: URL?
    public let externalPlaybackURL: URL?
    public let externalPlaybackContentType: String?
    public let externalPlaybackDuration: Double?
    public var lastPosition: Double? // Optional last playback position
    public let episodeIndex: Int?
    public let skipSegments: [PlayerSkipSegment]

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
                titleImageURL: URL? = nil,
                description: String? = nil,
                url: URL,
                posterUrl: URL? = nil,
                castVideoUrl: URL? = nil,
                externalPlaybackURL: URL? = nil,
                externalPlaybackContentType: String? = nil,
                externalPlaybackDuration: Double? = nil,
                lastPosition: Double? = nil,
                episodeIndex: Int? = nil,
                skipSegments: [PlayerSkipSegment] = [],
                playbackHealthAssetIdentifier: String? = nil,
                playbackHealthMonitoringEligible: Bool = false) {
        self.title = title
        self.titleImageURL = titleImageURL
        self.description = description
        self.url = url
        self.posterUrl = posterUrl
        self.castVideoUrl = castVideoUrl ?? externalPlaybackURL
        self.externalPlaybackURL = externalPlaybackURL ?? castVideoUrl
        self.externalPlaybackContentType = externalPlaybackContentType
        self.externalPlaybackDuration = externalPlaybackDuration
        self.lastPosition = lastPosition
        self.episodeIndex = episodeIndex
        self.skipSegments = skipSegments
        self.playbackHealthAssetIdentifier = playbackHealthAssetIdentifier
        self.playbackHealthMonitoringEligible = playbackHealthMonitoringEligible
    }
    #else
    public init(title: String,
                titleImageURL: URL? = nil,
                description: String? = nil,
                url: URL,
                posterUrl: URL? = nil,
                castVideoUrl: URL? = nil,
                externalPlaybackURL: URL? = nil,
                externalPlaybackContentType: String? = nil,
                externalPlaybackDuration: Double? = nil,
                lastPosition: Double? = nil,
                episodeIndex: Int? = nil,
                skipSegments: [PlayerSkipSegment] = []) {
        self.title = title
        self.titleImageURL = titleImageURL
        self.description = description
        self.url = url
        self.posterUrl = posterUrl
        self.castVideoUrl = castVideoUrl ?? externalPlaybackURL
        self.externalPlaybackURL = externalPlaybackURL ?? castVideoUrl
        self.externalPlaybackContentType = externalPlaybackContentType
        self.externalPlaybackDuration = externalPlaybackDuration
        self.lastPosition = lastPosition
        self.episodeIndex = episodeIndex
        self.skipSegments = skipSegments
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
