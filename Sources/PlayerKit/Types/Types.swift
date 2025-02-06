import Foundation

public enum PlayerType: String, CaseIterable, Identifiable, Codable {
    case vlcPlayer
    case avPlayer

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .vlcPlayer:
            return "VLC Player"
        case .avPlayer:
            return "AV Player"
        }
    }
}

enum SeekDirection: CustomStringConvertible {
    case forward
    case backward

    var description: String {
        switch self {
        case .forward:
            return "forward"
        case .backward:
            return "backward"
        }
    }
}

enum GestureStates: CustomStringConvertible {
    case idle
    case singleTapPending
    case multipleTapping

    var description: String {
        switch self {
        case .idle:
            return "idle"
        case .singleTapPending:
            return "singleTapPending"
        case .multipleTapping:
            return "multipleTapping"
        }
    }
}
