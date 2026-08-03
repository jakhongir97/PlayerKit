import Foundation
import MediaPlayer

/// What the lock screen and Control Center should currently show.
///
/// Deliberately a value type with `Equatable`: the coordinator publishes only
/// when this changes, because `MPNowPlayingInfoCenter` is meant to be told
/// about state *transitions*, not polled. The system extrapolates elapsed time
/// from `rate` and the moment of the last push, so republishing at PlayerKit's
/// 2 Hz runtime-state tick would be both wasteful and worse — every push resets
/// the system's own interpolation.
struct NowPlayingSnapshot: Equatable {
    var title: String
    var subtitle: String?
    /// `nil` for a stream with no usable timeline, which is what makes the
    /// lock-screen scrubber disappear rather than render as zero-length.
    var duration: Double?
    var elapsed: Double
    /// 0 while paused. Not the same as `playbackSpeed`, which stays at its
    /// configured value while paused.
    var rate: Double
    var isLive: Bool
}

/// Which transport controls the lock screen should offer, and what they do.
///
/// Availability is carried alongside the action so a control is never offered
/// when it would silently do nothing — the same posture the AirPlay affordance
/// already takes.
struct NowPlayingCommands {
    var play: () -> Void
    var pause: () -> Void
    var toggle: () -> Void
    var skipForward: (Double) -> Void
    var skipBackward: (Double) -> Void
    var seek: (Double) -> Void
    var canSeek: () -> Bool
    var next: () -> Void
    var canNext: () -> Bool
    var previous: () -> Void
    var canPrevious: () -> Bool
}

/// Owns the process-global now-playing info and remote command targets.
///
/// `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` are process-wide, so
/// this is the same hazard `GameControllerManager` exists for: a library that
/// installs handlers unconditionally takes them away from its host. It is
/// refcounted through `SharedResourceOwnership` for the same reason, and it
/// goes further in two ways that `MPRemoteCommand` specifically requires:
///
/// - every `addTarget` token is retained and removed individually. Calling
///   `removeTarget(nil)` would remove the *host's* targets too, which is a
///   worse version of the bug the controller refcounting just fixed;
/// - the host's prior `nowPlayingInfo` and each command's `isEnabled` are
///   snapshotted on acquisition and restored on release, so a host that had its
///   own now-playing state gets it back.
@MainActor
final class NowPlayingCoordinator {
    static let shared = NowPlayingCoordinator()

    let ownership = SharedResourceOwnership()

    /// Whether PlayerKit's command targets are currently installed. Tracked
    /// separately from ownership so the release path can be driven by "nobody
    /// holds this" rather than "the caller was the last owner".
    private(set) var areCommandsInstalled = false

    /// How many times the commands have actually been released, i.e. how many
    /// times the last remaining owner let go.
    private(set) var resourceReleaseCount = 0

    /// The last snapshot published, so an unchanged state is not republished.
    private(set) var lastPublishedSnapshot: NowPlayingSnapshot?

    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private var previousCommandEnablement: [(MPRemoteCommand, Bool)] = []
    private var previousSkipForwardIntervals: [NSNumber]?
    private var previousSkipBackwardIntervals: [NSNumber]?
    private var previousNowPlayingInfo: [String: Any]?
    private var artwork: MPMediaItemArtwork?

    private init() {}

    // MARK: - Ownership

    func installCommands(for owner: AnyObject, commands: NowPlayingCommands) {
        ownership.addOwner(owner)
        guard !areCommandsInstalled else { return }
        areCommandsInstalled = true

        let center = MPRemoteCommandCenter.shared()
        previousNowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo

        func add(_ command: MPRemoteCommand, enabled: Bool = true, handler: @escaping () -> Void) {
            previousCommandEnablement.append((command, command.isEnabled))
            command.isEnabled = enabled
            let token = command.addTarget { _ in
                handler()
                return .success
            }
            commandTargets.append((command, token))
        }

        add(center.playCommand, handler: commands.play)
        add(center.pauseCommand, handler: commands.pause)
        add(center.togglePlayPauseCommand, handler: commands.toggle)

        previousSkipForwardIntervals = center.skipForwardCommand.preferredIntervals
        previousSkipBackwardIntervals = center.skipBackwardCommand.preferredIntervals
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        add(center.skipForwardCommand) { commands.skipForward(Self.skipInterval) }
        add(center.skipBackwardCommand) { commands.skipBackward(Self.skipInterval) }

        // Scrubbing carries a payload, so it cannot use the helper above.
        previousCommandEnablement.append(
            (center.changePlaybackPositionCommand, center.changePlaybackPositionCommand.isEnabled)
        )
        center.changePlaybackPositionCommand.isEnabled = commands.canSeek()
        let seekToken = center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            commands.seek(event.positionTime)
            return .success
        }
        commandTargets.append((center.changePlaybackPositionCommand, seekToken))

        // Installed always, but enabled only while there is somewhere to go.
        // Offering a dead next-track button on a single movie is the same
        // failure as offering an AirPlay control that does nothing.
        add(center.nextTrackCommand, enabled: commands.canNext(), handler: commands.next)
        add(center.previousTrackCommand, enabled: commands.canPrevious(), handler: commands.previous)
    }

    func releaseCommands(for owner: AnyObject) {
        ownership.removeOwner(owner)
        // Release when nobody holds it, not merely when the caller happened to
        // be the last registered owner — same reasoning as GameControllerManager.
        guard !ownership.isHeld else { return }
        guard areCommandsInstalled else { return }
        areCommandsInstalled = false
        resourceReleaseCount += 1

        for (command, token) in commandTargets {
            command.removeTarget(token)
        }
        commandTargets.removeAll()

        for (command, wasEnabled) in previousCommandEnablement {
            command.isEnabled = wasEnabled
        }
        previousCommandEnablement.removeAll()

        let center = MPRemoteCommandCenter.shared()
        if let previousSkipForwardIntervals {
            center.skipForwardCommand.preferredIntervals = previousSkipForwardIntervals
        }
        if let previousSkipBackwardIntervals {
            center.skipBackwardCommand.preferredIntervals = previousSkipBackwardIntervals
        }
        previousSkipForwardIntervals = nil
        previousSkipBackwardIntervals = nil

        MPNowPlayingInfoCenter.default().nowPlayingInfo = previousNowPlayingInfo
        previousNowPlayingInfo = nil
        lastPublishedSnapshot = nil
        artwork = nil
    }

    // MARK: - Publishing

    /// The step the lock screen's skip buttons take, in seconds.
    static let skipInterval: Double = 15

    func setArtwork(_ image: PKImage?) {
        guard let image else {
            artwork = nil
            lastPublishedSnapshot = nil
            return
        }
        artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        // Force the next publish through: artwork is not part of the snapshot's
        // equality, so a change would otherwise be swallowed by the dirty check.
        lastPublishedSnapshot = nil
    }

    /// Publishes `snapshot`, unless it is identical to the last one published.
    func publish(_ snapshot: NowPlayingSnapshot) {
        guard areCommandsInstalled else { return }
        guard snapshot != lastPublishedSnapshot else { return }
        lastPublishedSnapshot = snapshot

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: snapshot.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.rate,
            MPNowPlayingInfoPropertyIsLiveStream: snapshot.isLive,
        ]
        if let subtitle = snapshot.subtitle, !subtitle.isEmpty {
            info[MPMediaItemPropertyArtist] = subtitle
        }
        // Omitted entirely for a stream with no usable timeline; publishing 0
        // renders a zero-length scrubber rather than hiding it.
        if let duration = snapshot.duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Updates which transport controls the lock screen currently offers.
    ///
    /// Availability moves with playback — a queue can run out, and a stream can
    /// lose its seekable window — so this is refreshed alongside the metadata
    /// rather than fixed at install time.
    func updateAvailability(canSeek: Bool, canNext: Bool, canPrevious: Bool) {
        guard areCommandsInstalled else { return }
        let center = MPRemoteCommandCenter.shared()
        center.changePlaybackPositionCommand.isEnabled = canSeek
        center.nextTrackCommand.isEnabled = canNext
        center.previousTrackCommand.isEnabled = canPrevious
    }

    /// Clears the now-playing item without giving up ownership, for when
    /// playback stops but the player is still on screen.
    func clearNowPlayingItem() {
        guard areCommandsInstalled else { return }
        lastPublishedSnapshot = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
