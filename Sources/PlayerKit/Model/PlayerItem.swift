import SwiftUI

public struct PlayerItem {
    public let title: String
    public let description: String?
    public let url: URL
    public let posterUrl: URL?
    public let castVideoUrl: URL?
    public var lastPosition: Double? // Optional last playback position
    public let episodeIndex: Int?
    
    // Add a public initializer
    public init(title: String, 
                description: String? = nil,
                url: URL, posterUrl: URL? = nil,
                castVideoUrl: URL? = nil,
                lastPosition: Double? = nil,
                episodeIndex: Int? = nil) {
        self.title = title
        self.description = description
        self.url = url
        self.posterUrl = posterUrl
        self.castVideoUrl = castVideoUrl
        self.lastPosition = lastPosition
        self.episodeIndex = episodeIndex
    }
}

public enum PlayerContentType {
    case movie
    case episode
}
