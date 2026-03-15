import Foundation

public enum PlayerType: String, CaseIterable, Identifiable, Codable {
    case vlcPlayer
    case avPlayer

    public var id: String { rawValue }

    public static var supportedCases: [PlayerType] {
        #if canImport(VLCKit)
        [.vlcPlayer, .avPlayer]
        #elseif os(macOS)
        desktopVLCAvailability ? [.vlcPlayer, .avPlayer] : [.avPlayer]
        #else
        [.avPlayer]
        #endif
    }

    public var isSupported: Bool {
        Self.supportedCases.contains(self)
    }

    static func resolved(_ preferred: PlayerType?) -> PlayerType {
        guard let preferred, preferred.isSupported else { return .avPlayer }
        return preferred
    }

    var title: String {
        switch self {
        case .vlcPlayer:
            return "VLC Player"
        case .avPlayer:
            return "AV Player"
        }
    }
}

#if os(macOS)
private let desktopVLCAvailability: Bool = {
    let processInfo = ProcessInfo.processInfo
    if processInfo.processName == "xctest" {
        return false
    }
    if processInfo.arguments.contains(where: { $0.hasSuffix(".xctest") }) {
        return false
    }
    if Bundle.allBundles.contains(where: { $0.bundlePath.hasSuffix(".xctest") }) {
        return false
    }
    guard processInfo.environment["XCTestConfigurationFilePath"] == nil else {
        return false
    }
    let fileManager = FileManager.default
    let libDirectory = "/Applications/VLC.app/Contents/MacOS/lib"
    return fileManager.fileExists(atPath: "\(libDirectory)/libvlc.dylib")
        && fileManager.fileExists(atPath: "\(libDirectory)/libvlccore.dylib")
}()
#endif

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
