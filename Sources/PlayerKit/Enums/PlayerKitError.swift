import Foundation

public enum PlayerKitError: Error, Equatable, LocalizedError {
    case mediaLoadFailed(String)
    case pictureInPictureFailed(String)
    case castSessionUnavailable
    case castURLMissing
    case externalPlaybackDeviceUnavailable
    case externalPlaybackURLMissing
    case externalPlaybackRequiresReachableURL
    case externalPlaybackFailed(String)
    case unknown(String)

    /// A stable, non-diagnostic description that is safe to present in host UI.
    ///
    /// The associated strings carried by some cases remain available through
    /// `errorDescription` for source compatibility. Treat those strings as
    /// private diagnostics: never put credentials, signed URLs, or tokens in them.
    public var userFacingDescription: String {
        userFacingDescription(using: PlayerStrings())
    }

    /// Returns the safe product message from host-supplied player copy.
    public func userFacingDescription(using strings: PlayerStrings) -> String {
        switch self {
        case .mediaLoadFailed:
            return strings.mediaLoadFailedDescription
        case .pictureInPictureFailed:
            return strings.pictureInPictureFailedDescription
        case .castSessionUnavailable, .castURLMissing:
            return strings.castingFailedDescription
        case .externalPlaybackDeviceUnavailable,
             .externalPlaybackURLMissing,
             .externalPlaybackRequiresReachableURL,
             .externalPlaybackFailed:
            return strings.externalPlaybackFailedDescription
        case .unknown:
            return strings.actionFailedDescription
        }
    }

    public var errorDescription: String? {
        switch self {
        case .mediaLoadFailed(let description):
            return "Failed to load media: \(description)"
        case .pictureInPictureFailed(let description):
            return "Picture in Picture failed: \(description)"
        case .castSessionUnavailable:
            return "Cast session is unavailable."
        case .castURLMissing:
            return "Cast URL is missing for the current item."
        case .externalPlaybackDeviceUnavailable:
            return "No external playback device is selected."
        case .externalPlaybackURLMissing:
            return "No reachable external playback URL is available for the current item."
        case .externalPlaybackRequiresReachableURL:
            return "External playback currently requires an http or https media URL."
        case .externalPlaybackFailed(let description):
            return "External playback failed: \(description)"
        case .unknown(let description):
            return description
        }
    }
}
