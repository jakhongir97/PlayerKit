#if os(macOS)
import Foundation

public enum PlaybackHealthSignalKind: String, Sendable, Hashable {
    case playlistRequestFailure
    case mediaSegmentRequestFailure
    case contentKeyRequestFailure
    case errorLogEntry
    case playbackStall
}

public enum PlaybackHealthConfidence: String, Sendable, Hashable {
    case low
    case medium
    case high
}

public enum PlaybackHealthMediaType: String, Sendable, Hashable {
    case audio
    case video
    case muxed
    case unknown
}

public struct PlaybackHealthAudioTrack: Sendable, Hashable {
    public let identifier: String
    public let languageCode: String?
    public let displayName: String?
    public let isSelected: Bool

    public init(
        identifier: String,
        languageCode: String?,
        displayName: String?,
        isSelected: Bool
    ) {
        self.identifier = identifier
        self.languageCode = languageCode
        self.displayName = displayName
        self.isSelected = isSelected
    }
}

public struct PlaybackHealthEvent: Sendable, Hashable {
    public let healthSessionID: UUID
    public let assetIdentifier: String?
    public let signalKind: PlaybackHealthSignalKind
    public let confidence: PlaybackHealthConfidence
    public let mediaType: PlaybackHealthMediaType
    public let mediaTime: Double?
    public let selectedAudioTrack: PlaybackHealthAudioTrack?
    public let errorDomain: String?
    public let errorCode: Int?
    public let didRecover: Bool?
    public let occurredAt: Date

    public init(
        healthSessionID: UUID,
        assetIdentifier: String?,
        signalKind: PlaybackHealthSignalKind,
        confidence: PlaybackHealthConfidence,
        mediaType: PlaybackHealthMediaType,
        mediaTime: Double?,
        selectedAudioTrack: PlaybackHealthAudioTrack?,
        errorDomain: String?,
        errorCode: Int?,
        didRecover: Bool?,
        occurredAt: Date
    ) {
        self.healthSessionID = healthSessionID
        self.assetIdentifier = assetIdentifier
        self.signalKind = signalKind
        self.confidence = confidence
        self.mediaType = mediaType
        self.mediaTime = mediaTime
        self.selectedAudioTrack = selectedAudioTrack
        self.errorDomain = errorDomain
        self.errorCode = errorCode
        self.didRecover = didRecover
        self.occurredAt = occurredAt
    }
}
#endif
