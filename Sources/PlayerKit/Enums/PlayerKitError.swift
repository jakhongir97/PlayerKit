import Foundation

public enum PlayerKitError: Error, Equatable, LocalizedError {
    case mediaLoadFailed(String)
    case castSessionUnavailable
    case castURLMissing
    case externalPlaybackDeviceUnavailable
    case externalPlaybackURLMissing
    case externalPlaybackRequiresReachableURL
    case externalPlaybackFailed(String)
    case dubberNotConfigured
    case dubberSourceMissing
    case dubberRequestFailed(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .mediaLoadFailed(let description):
            return "Failed to load media: \(description)"
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
        case .dubberNotConfigured:
            return "Dubber integration is not configured."
        case .dubberSourceMissing:
            return "No source media available for Dubber."
        case .dubberRequestFailed(let description):
            return "Dubber request failed: \(description)"
        case .unknown(let description):
            return description
        }
    }
}
