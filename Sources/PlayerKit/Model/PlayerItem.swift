import SwiftUI

public struct PlayerItem {
    public let title: String
    public let description: String?
    public let url: URL
    public var lastPosition: Double? // Optional last playback position
    
    // Add a public initializer
    public init(title: String, description: String? = nil, url: URL, lastPosition: Double? = nil) {
        self.title = title
        self.description = description
        self.url = url
        self.lastPosition = lastPosition
    }
}
