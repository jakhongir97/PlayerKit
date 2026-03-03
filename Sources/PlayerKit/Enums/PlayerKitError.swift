import Foundation

public enum PlayerKitError: Error, Equatable, LocalizedError {
    case mediaLoadFailed(String)
    case castSessionUnavailable
    case castURLMissing
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
