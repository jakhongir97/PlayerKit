import Foundation

/// Privacy-safe playback lifecycle facts for host analytics.
///
/// PlayerKit does not attach media URLs, titles, backend diagnostics, or user
/// identifiers. The callback is delivered synchronously on `PlayerManager`'s
/// main actor, so a host can add its own item/session context at that boundary.
public enum PlayerQoEEvent: Equatable, Sendable {
    case loadRequested(autoplay: Bool)
    case playRequested
    case pauseRequested
    case ready
    /// The backend reported active, non-buffering playback. This is not a
    /// decoded-first-frame measurement.
    case playbackStarted
    case stallStarted
    case stallEnded
    case seekCompleted(targetTime: Double, succeeded: Bool)
    case fatalError
    case completed
    case exited
}

struct PlayerQoEEventReducer {
    private var hasLoad = false
    private var isReady = false
    private var runtimeIsPlaying = false
    private var didStartPlayback = false
    private var hasActiveStall = false
    private var isTerminal = false
    private var didExit = false

    mutating func loadRequested(autoplay: Bool) -> [PlayerQoEEvent] {
        self = Self()
        hasLoad = true
        return [.loadRequested(autoplay: autoplay)]
    }

    mutating func playRequested() -> [PlayerQoEEvent] {
        guard acceptsPlaybackEvents else { return [] }
        return [.playRequested]
    }

    mutating func pauseRequested() -> [PlayerQoEEvent] {
        guard acceptsPlaybackEvents else { return [] }
        return [.pauseRequested]
    }

    mutating func ready() -> [PlayerQoEEvent] {
        guard acceptsPlaybackEvents, !isReady else { return [] }
        isReady = true
        var events: [PlayerQoEEvent] = [.ready]
        if runtimeIsPlaying, !didStartPlayback {
            didStartPlayback = true
            events.append(.playbackStarted)
        }
        return events
    }

    mutating func runtimeChanged(isPlaying: Bool, isBuffering: Bool) -> [PlayerQoEEvent] {
        guard acceptsPlaybackEvents else { return [] }
        runtimeIsPlaying = isPlaying && !isBuffering

        var events: [PlayerQoEEvent] = []
        if hasActiveStall, !isBuffering {
            hasActiveStall = false
            events.append(.stallEnded)
        }
        if isReady, runtimeIsPlaying, !didStartPlayback {
            didStartPlayback = true
            events.append(.playbackStarted)
        }
        return events
    }

    mutating func stallStarted() -> [PlayerQoEEvent] {
        guard acceptsPlaybackEvents, didStartPlayback, !hasActiveStall else { return [] }
        hasActiveStall = true
        return [.stallStarted]
    }

    mutating func seekCompleted(targetTime: Double, succeeded: Bool) -> [PlayerQoEEvent] {
        guard acceptsPlaybackEvents, targetTime.isFinite, targetTime >= 0 else { return [] }
        return [.seekCompleted(targetTime: targetTime, succeeded: succeeded)]
    }

    mutating func fatalError() -> [PlayerQoEEvent] {
        finish(with: .fatalError)
    }

    mutating func completed() -> [PlayerQoEEvent] {
        finish(with: .completed)
    }

    mutating func exited() -> [PlayerQoEEvent] {
        guard hasLoad, !didExit else { return [] }
        var events = endActiveStall()
        didExit = true
        events.append(.exited)
        return events
    }

    private var acceptsPlaybackEvents: Bool {
        hasLoad && !isTerminal && !didExit
    }

    private mutating func finish(with terminalEvent: PlayerQoEEvent) -> [PlayerQoEEvent] {
        guard acceptsPlaybackEvents else { return [] }
        var events = endActiveStall()
        isTerminal = true
        events.append(terminalEvent)
        return events
    }

    private mutating func endActiveStall() -> [PlayerQoEEvent] {
        guard hasActiveStall else { return [] }
        hasActiveStall = false
        return [.stallEnded]
    }
}
