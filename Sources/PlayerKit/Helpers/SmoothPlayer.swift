import AVFoundation

private struct SmoothPlayerPendingSeek: Sendable {
    let time: CMTime
    let toleranceBefore: CMTime
    let toleranceAfter: CMTime
}

/// AVPlayer invokes seek completions off the main actor. Keep only the small,
/// lock-protected coalescing state there; the public player surface remains
/// main-actor isolated.
private final class SmoothPlayerSeekState: @unchecked Sendable {
    private let lock = NSLock()
    private var isSeeking = false
    private var pendingSeek: SmoothPlayerPendingSeek?
    private var generation: UInt64 = 0
    private var handlers: [(Bool) -> Void] = []

    func enqueue(
        _ request: SmoothPlayerPendingSeek,
        completion: @escaping (Bool) -> Void
    ) -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        handlers.append(completion)
        guard !isSeeking else {
            pendingSeek = request
            return nil
        }
        isSeeking = true
        return generation
    }

    func complete(
        generation expectedGeneration: UInt64
    ) -> (next: SmoothPlayerPendingSeek?, handlers: [(Bool) -> Void]?, isStale: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == expectedGeneration else {
            return (nil, nil, true)
        }
        if let pendingSeek {
            self.pendingSeek = nil
            return (pendingSeek, nil, false)
        }
        let completedHandlers = handlers
        handlers.removeAll()
        isSeeking = false
        return (nil, completedHandlers, false)
    }

    func cancel() -> [(Bool) -> Void] {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        let cancelledHandlers = handlers
        handlers.removeAll()
        pendingSeek = nil
        isSeeking = false
        return cancelledHandlers
    }
}

/// An `AVPlayer` subclass that coalesces bursts of seek requests.
///
/// Scrubbing an HLS stream can produce a seek per frame of drag, and issuing
/// each one is expensive. This collapses a burst so only the newest target is
/// actually seeked to.
///
/// Three things this deliberately gets right, none of which the previous
/// implementation did:
///
/// - **No completion handler is dropped.** Superseded requests used to have
///   their handler silently overwritten, so callers waiting on a seek were
///   never called back at all. Every handler is now retained and invoked once
///   the coalesced seek settles.
/// - **Tolerances belong to their request.** The queued seek used to be
///   replayed with the *previous* request's tolerances, quietly discarding the
///   zero tolerance that `seekExactly(to:)` depends on.
/// - **State is synchronized.** `AVPlayer` delivers seek completions on an
///   internal queue, so the coalescing state is touched from at least two
///   threads.
final class SmoothPlayer: AVPlayer {
    private let seekState = SmoothPlayerSeekState()

    // MARK: - Overridden Seek Methods

    nonisolated override func seek(to time: CMTime) {
        seek(to: time, completionHandler: { _ in })
    }

    nonisolated override func seek(to time: CMTime, completionHandler: @escaping (Bool) -> Void) {
        seek(
            to: time,
            toleranceBefore: CMTime(seconds: 0.5, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 600),
            completionHandler: completionHandler
        )
    }

    /// Overridden so this variant is coalesced too; previously it bypassed the
    /// coalescing entirely and could race a tracked seek.
    nonisolated override func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) {
        seek(
            to: time,
            toleranceBefore: toleranceBefore,
            toleranceAfter: toleranceAfter,
            completionHandler: { _ in }
        )
    }

    nonisolated override func seek(
        to time: CMTime,
        toleranceBefore: CMTime,
        toleranceAfter: CMTime,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let request = SmoothPlayerPendingSeek(
            time: time,
            toleranceBefore: toleranceBefore,
            toleranceAfter: toleranceAfter
        )

        guard let generation = seekState.enqueue(request, completion: completionHandler) else {
            // Fold into the in-flight seek. The handler stays queued, so this
            // caller is still notified once the burst settles.
            Self.debugLog("Queueing follow-up seek to \(Self.debugTime(time)) while another seek is active.")
            return
        }

        Self.debugLog("Starting seek to \(Self.debugTime(time)).")
        perform(request, generation: generation)
    }

    private nonisolated func perform(_ request: SmoothPlayerPendingSeek, generation: UInt64) {
        super.seek(
            to: request.time,
            toleranceBefore: request.toleranceBefore,
            toleranceAfter: request.toleranceAfter
        ) { [weak self] finished in
            self?.handleSeekCompletion(finished, generation: generation)
        }
    }

    /// Runs the newest queued request if one arrived mid-seek; otherwise drains
    /// every accumulated completion handler exactly once.
    private nonisolated func handleSeekCompletion(_ finished: Bool, generation: UInt64) {
        let result = seekState.complete(generation: generation)
        guard !result.isStale else { return }
        if let next = result.next {
            Self.debugLog(
                "Seek completed with a queued follow-up target at \(Self.debugTime(next.time)). " +
                "finished=\(finished)"
            )
            perform(next, generation: generation)
            return
        }

        let handlers = result.handlers ?? []

        Self.debugLog("Seek finished=\(finished) handlers=\(handlers.count)")
        for handler in handlers {
            handler(finished)
        }
    }

    /// Drops queued work and reports failure to everyone still waiting.
    ///
    /// Called when the item is replaced or the player is torn down, so callers
    /// are not left holding a completion that can never fire.
    nonisolated func cancelCoalescedSeeks() {
        let handlers = seekState.cancel()
        for handler in handlers {
            handler(false)
        }
    }

    private nonisolated static func debugTime(_ time: CMTime) -> String {
        let seconds = time.seconds
        guard seconds.isFinite else { return "nan" }
        return String(format: "%.3f", seconds)
    }

    private nonisolated static func debugLog(_ message: @autoclosure () -> String) {
        PlayerKitLog.debug("SmoothPlayer", message())
    }
}
