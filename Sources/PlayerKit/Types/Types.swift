import Foundation

public enum PlayerType {
    case avPlayer
    case vlcPlayer

    // Computed property to provide a more descriptive title
    public var title: String {
        switch self {
        case .avPlayer:
            return "AV Player"
        case .vlcPlayer:
            return "VLC Player"
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

enum GestureState: CustomStringConvertible {
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
