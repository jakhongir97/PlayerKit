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
    
    // Add a public initializer
    public init(title: String, 
                description: String? = nil,
                url: URL, posterUrl: URL? = nil,
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
}

extension PlayerItem {
    var preferredExternalPlaybackURL: URL? {
        externalPlaybackURL ?? castVideoUrl ?? (!url.isFileURL ? url : nil)
    }
}

public enum PlayerContentType {
    case movie
    case episode
}
