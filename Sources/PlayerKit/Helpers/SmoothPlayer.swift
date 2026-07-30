import AVFoundation

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
    private struct PendingSeek {
        let time: CMTime
        let toleranceBefore: CMTime
        let toleranceAfter: CMTime
    }

    private let stateLock = NSLock()
    private var isSeeking = false
    private var pendingSeek: PendingSeek?
    /// Handlers for every request folded into the in-flight seek.
    private var pendingCompletionHandlers: [(Bool) -> Void] = []

    /// Tolerances tuned for HLS; used when a caller does not specify its own.
    private let hlsToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
    private let hlsToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

    // MARK: - Overridden Seek Methods

    override func seek(to time: CMTime) {
        seek(to: time, completionHandler: { _ in })
    }

    override func seek(to time: CMTime, completionHandler: @escaping (Bool) -> Void) {
        seek(
            to: time,
            toleranceBefore: hlsToleranceBefore,
            toleranceAfter: hlsToleranceAfter,
            completionHandler: completionHandler
        )
    }

    /// Overridden so this variant is coalesced too; previously it bypassed the
    /// coalescing entirely and could race a tracked seek.
    override func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) {
        seek(
            to: time,
            toleranceBefore: toleranceBefore,
            toleranceAfter: toleranceAfter,
            completionHandler: { _ in }
        )
    }

    override func seek(
        to time: CMTime,
        toleranceBefore: CMTime,
        toleranceAfter: CMTime,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let request = PendingSeek(
            time: time,
            toleranceBefore: toleranceBefore,
            toleranceAfter: toleranceAfter
        )

        stateLock.lock()
        pendingCompletionHandlers.append(completionHandler)
        if isSeeking {
            // Fold into the in-flight seek. The handler stays queued, so this
            // caller is still notified once the burst settles.
            pendingSeek = request
            stateLock.unlock()
            debugLog("Queueing follow-up seek to \(debugTime(time)) while another seek is active.")
            return
        }
        isSeeking = true
        stateLock.unlock()

        debugLog("Starting seek to \(debugTime(time)).")
        perform(request)
    }

    private func perform(_ request: PendingSeek) {
        super.seek(
            to: request.time,
            toleranceBefore: request.toleranceBefore,
            toleranceAfter: request.toleranceAfter
        ) { [weak self] finished in
            self?.handleSeekCompletion(finished)
        }
    }

    /// Runs the newest queued request if one arrived mid-seek; otherwise drains
    /// every accumulated completion handler exactly once.
    private func handleSeekCompletion(_ finished: Bool) {
        stateLock.lock()
        if let next = pendingSeek {
            pendingSeek = nil
            stateLock.unlock()
            debugLog(
                "Seek completed with a queued follow-up target at \(debugTime(next.time)). " +
                "finished=\(finished)"
            )
            perform(next)
            return
        }

        let handlers = pendingCompletionHandlers
        pendingCompletionHandlers.removeAll()
        isSeeking = false
        stateLock.unlock()

        debugLog("Seek finished=\(finished) handlers=\(handlers.count)")
        for handler in handlers {
            handler(finished)
        }
    }

    /// Drops queued work and reports failure to everyone still waiting.
    ///
    /// Called when the item is replaced or the player is torn down, so callers
    /// are not left holding a completion that can never fire.
    func cancelCoalescedSeeks() {
        stateLock.lock()
        let handlers = pendingCompletionHandlers
        pendingCompletionHandlers.removeAll()
        pendingSeek = nil
        isSeeking = false
        stateLock.unlock()

        for handler in handlers {
            handler(false)
        }
    }

    private func debugTime(_ time: CMTime) -> String {
        let seconds = time.seconds
        guard seconds.isFinite else { return "nan" }
        return String(format: "%.3f", seconds)
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        PlayerKitLog.debug("SmoothPlayer", message())
    }
}
