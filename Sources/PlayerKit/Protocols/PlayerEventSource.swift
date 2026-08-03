import Foundation

public struct PlayerRuntimeState: Sendable {
    public let isPlaying: Bool
    public let isBuffering: Bool
    public let currentTime: Double
    public let duration: Double
    public let bufferedDuration: Double

    public init(
        isPlaying: Bool,
        isBuffering: Bool,
        currentTime: Double,
        duration: Double,
        bufferedDuration: Double
    ) {
        self.isPlaying = isPlaying
        self.isBuffering = isBuffering
        self.currentTime = currentTime
        self.duration = duration
        self.bufferedDuration = bufferedDuration
    }
}

@MainActor
/// Receives lifecycle events from a custom player backend installed with
/// `PlayerManager.installPlayerBackend(_:)`.
public protocol PlayerLifecycleReporting: AnyObject {
    func playerDidBecomeReady()
    func playerDidUpdateTracks()
    func playerDidEndPlayback()
    func playerDidChangePiPState(isActive: Bool)
    func playerDidStall()
    func playerDidFail(with error: PlayerKitError)
    /// Reports a recoverable feature failure without stopping local playback.
    func playerDidEncounterNonfatalError(_ error: PlayerKitError)
}

public extension PlayerLifecycleReporting {
    /// Compatibility default for existing custom lifecycle reporters.
    func playerDidEncounterNonfatalError(_ error: PlayerKitError) {}
}

@MainActor
/// Adopt this alongside `PlayerProtocol` when a custom backend needs to report
/// readiness, track changes, stalls, completion, PiP, or terminal failures.
public protocol PlayerEventSource: AnyObject {
    var lifecycleReporter: PlayerLifecycleReporting? { get set }
}

@MainActor
public protocol PlayerStateSource: AnyObject {
    var onRuntimeStateChange: ((PlayerRuntimeState) -> Void)? { get set }
    func startRuntimeStateUpdates()
    func stopRuntimeStateUpdates()
}

/// Lets the manager avoid publishing optimistic playback after a backend has
/// no item (for example before load or after a terminal construction failure).
@MainActor
public protocol PlayerMediaAvailabilityReporting: AnyObject {
    var hasLoadedMedia: Bool { get }
}
