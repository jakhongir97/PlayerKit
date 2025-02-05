import AVFoundation

/// A custom AVPlayer subclass that optimizes seek handling for HLS streaming.
/// Instead of performing every seek call (which can be expensive for HLS),
/// it only executes the final requested seek when multiple seek requests come in quickly.
class SmoothPlayer: AVPlayer {
    /// Indicates whether a seek operation is currently in progress.
    private var isSeeking = false
    /// Holds the most recent (pending) seek time if a new request arrives while already seeking.
    private var pendingSeekTime: CMTime?
    /// Holds the completion handler for the pending seek.
    private var pendingCompletionHandler: ((Bool) -> Void)?
    
    /// Tolerance values tuned for HLS (adjust these as needed).
    private let hlsToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
    private let hlsToleranceAfter  = CMTime(seconds: 0.5, preferredTimescale: 600)
    
    // MARK: - Overridden Seek Methods

    /// A convenience override that calls our custom implementation.
    override func seek(to time: CMTime) {
        seek(to: time, completionHandler: { _ in })
    }

    /// Override the basic seek call to use HLS-friendly tolerances.
    override func seek(to time: CMTime, completionHandler: @escaping (Bool) -> Void) {
        seek(to: time, toleranceBefore: hlsToleranceBefore, toleranceAfter: hlsToleranceAfter, completionHandler: completionHandler)
    }
    
    /// The core implementation: if a seek is already in progress, simply update the pending target time.
    /// Once the current seek completes, if a pending time exists, perform that seek.
    override func seek(to time: CMTime,
                       toleranceBefore: CMTime,
                       toleranceAfter: CMTime,
                       completionHandler: @escaping (Bool) -> Void) {
        // If a seek is in progress, update the pending target.
        if isSeeking {
            pendingSeekTime = time
            pendingCompletionHandler = completionHandler
            return
        }
        
        // No seek in progress—start one.
        isSeeking = true
        super.seek(to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter) { [weak self] finished in
            guard let self = self else { return }
            self.handleSeekCompletion(finished, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter)
        }
    }
    
    /// Handles the completion of a seek. If a new seek request has come in while the current seek was in progress,
    /// immediately execute that (latest) request. Otherwise, finish up by resetting our flags and calling any pending completion.
    private func handleSeekCompletion(_ finished: Bool,
                                      toleranceBefore: CMTime,
                                      toleranceAfter: CMTime) {
        if let newTime = pendingSeekTime {
            // A new seek was requested during the previous seek.
            pendingSeekTime = nil
            super.seek(to: newTime, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter) { [weak self] newFinished in
                guard let self = self else { return }
                self.handleSeekCompletion(newFinished, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter)
            }
        } else {
            // No more pending seeks; mark seeking as finished.
            isSeeking = false
            // Call the last completion handler if one was provided.
            pendingCompletionHandler?(finished)
            pendingCompletionHandler = nil
        }
    }
}

