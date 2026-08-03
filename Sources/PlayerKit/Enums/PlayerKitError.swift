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
    /// Associated strings remain available by pattern matching for internal
    /// diagnosis, but neither presentation API returns them.
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
        userFacingDescription
    }
}
