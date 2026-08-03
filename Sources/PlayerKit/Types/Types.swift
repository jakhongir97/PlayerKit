import CoreGraphics
import Foundation

public enum PlayerType: String, CaseIterable, Identifiable, Codable {
    case vlcPlayer
    case avPlayer

    public var id: String { rawValue }

    public static var supportedCases: [PlayerType] {
        #if os(macOS)
        desktopVLCAvailability ? [.vlcPlayer, .avPlayer] : [.avPlayer]
        #elseif canImport(VLCKit)
        [.vlcPlayer, .avPlayer]
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
    return DesktopVLCPlayerWrapper.isRuntimeAvailable
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

/// Everything the double-tap seek overlay needs to draw itself.
///
/// One value describes a whole seek session: the side it runs on, how much has
/// been skipped so far, and where the most recent tap landed so the ring can
/// open from the fingertip. `tapID` counts taps within the session, and is what
/// replays the per-tap animations without rebuilding the readout around them —
/// a counter rather than a `UUID`, since it only has to differ from the tap
/// before it, and an `Int` compares without touching the random pool.
struct DoubleTapSeekOverlayState: Equatable {
    let direction: SeekDirection
    /// Seconds accumulated across the session, e.g. 10, 20, 30…
    let seconds: Double
    /// Where the tap landed, as a fraction of the surface in each axis.
    ///
    /// Stored as a unit point rather than raw points so a rotation mid-session
    /// cannot strand the ripple off-screen: the origin was previously captured
    /// against the pre-rotation size and then drawn against the new one.
    let unitOrigin: CGPoint
    let tapID: Int

    /// The draw-time position for a given surface.
    func origin(in size: CGSize) -> CGPoint {
        CGPoint(x: unitOrigin.x * size.width, y: unitOrigin.y * size.height)
    }
}
