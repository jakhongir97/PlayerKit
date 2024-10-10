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

