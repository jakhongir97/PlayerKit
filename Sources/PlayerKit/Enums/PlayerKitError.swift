import Foundation

public enum PlayerKitError: Error, Equatable, LocalizedError {
    case mediaLoadFailed(String)
    case castSessionUnavailable
    case castURLMissing
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .mediaLoadFailed(let description):
            return "Failed to load media: \(description)"
        case .castSessionUnavailable:
            return "Cast session is unavailable."
        case .castURLMissing:
            return "Cast URL is missing for the current item."
        case .unknown(let description):
            return description
        }
    }
}
