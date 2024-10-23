import SwiftUI
import Combine

public class GestureManager: ObservableObject {
    // MARK: - Published Properties
    @Published var visualFeedback: String?
    @Published var feedbackImage: Image?
    @Published var feedbackID: UUID? // Use an identifier to trigger FeedbackView

    // MARK: - Callback Closures
    var onSeek: ((_ newTime: Double) -> Void)?
    var onToggleControls: (() -> Void)?
    var onZoom: ((_ scale: CGFloat) -> Void)?
    
    // MARK: - Private Properties
    private var accumulatedInterval: Double = 0.0
    private var seekDirection: SeekDirection = .forward
    private var lastSeekDirection: SeekDirection?
    private var gestureState: GestureState = .idle
    private var isRightSide: Bool = true
    private var tapDelayTimer: Timer?
    private var multipleTapResetTimer: Timer?
    private var initialTime: Double?

    // Constants
    private let tapDelay = 0.3 // Delay to distinguish single tap
    private let multipleTapResetDelay = 1.0 // Delay to reset multiple tapping
    private let fastSeekBaseInterval: Double = 10.0 // Base seek interval

    // MARK: - Public Methods
    
    /// Handles the pinch gesture from the view.
    func handlePinch(scale: CGFloat) {
        print("[GestureManager] handlePinch - scale: \(scale)")
        onZoom?(scale)  // Trigger the zoom action
    }

    /// Handles the tap gesture from the view.
    func handleTap(at location: CGPoint, in size: CGSize) {
        isRightSide = location.x > size.width / 2
        let direction: SeekDirection = isRightSide ? .forward : .backward

        print("[GestureManager] handleTap - location: \(location), isRightSide: \(isRightSide), gestureState: \(gestureState)")

        switch gestureState {
        case .idle:
            gestureState = .singleTapPending
            print("[GestureManager] State changed to singleTapPending")
            startTapDelayTimer()

        case .singleTapPending:
            invalidateTapDelayTimer()
            gestureState = .multipleTapping
            print("[GestureManager] State changed to multipleTapping")
            // Store the initial time
            if initialTime == nil {
                initialTime = PlayerManager.shared.currentPlayer?.currentTime
                print("[GestureManager] Stored initialTime: \(initialTime ?? 0.0)")
            }
            PlayerManager.shared.areControlsVisible = false
            lastSeekDirection = direction
            handleMultipleTap(direction: direction)
            startMultipleTapResetTimer()

        case .multipleTapping:
            // If direction has changed, reset accumulatedInterval and initialTime
            if direction != lastSeekDirection {
                print("[GestureManager] Direction changed during multiple tapping. Resetting accumulatedInterval and initialTime.")
                resetAccumulatedInterval()
                initialTime = PlayerManager.shared.currentPlayer?.currentTime
                lastSeekDirection = direction
            }
            handleMultipleTap(direction: direction)
            resetMultipleTapResetTimer()
        }
    }

    /// Calculates the feedback position based on the tap location.
    func feedbackPosition(in size: CGSize) -> CGFloat {
        isRightSide ? size.width * 0.75 : size.width * 0.25
    }

    // MARK: - Private Methods

    /// Handles a single tap action to toggle the controls.
    private func handleSingleTap() {
        print("[GestureManager] handleSingleTap - Toggling controls")
        onToggleControls?()
    }

    /// Handles a multiple tap action for fast seeking.
    private func handleMultipleTap(direction: SeekDirection) {
        seekDirection = direction
        accumulatedInterval += fastSeekBaseInterval
        print("[GestureManager] handleMultipleTap - direction: \(direction), accumulatedInterval: \(accumulatedInterval)")
        performSeek()
        showVisualFeedback()
    }

    /// Resets the accumulated seek interval.
    private func resetAccumulatedInterval() {
        print("[GestureManager] resetAccumulatedInterval")
        accumulatedInterval = 0.0
    }

    /// Performs the seek operation.
    private func performSeek() {
        guard let currentPlayer = PlayerManager.shared.currentPlayer else {
            print("[GestureManager] performSeek - currentPlayer is nil")
            return
        }
        guard let initialTime = initialTime else {
            print("[GestureManager] performSeek - initialTime is nil")
            return
        }
        let interval = accumulatedInterval
        let totalDuration = currentPlayer.duration
        let newTime = max(0, min(totalDuration, initialTime + (seekDirection == .forward ? interval : -interval)))
        print("[GestureManager] performSeek - initialTime: \(initialTime), newTime: \(newTime), totalDuration: \(totalDuration)")
        PlayerManager.shared.seek(to: newTime)
    }

    /// Shows visual feedback for the seek operation.
    private func showVisualFeedback() {
        // Generate a new feedbackID to trigger the view update
        feedbackID = UUID()

        let feedbackText = seekDirection == .forward ? "\(Int(accumulatedInterval))s" : "\(-Int(accumulatedInterval))s"
        visualFeedback = feedbackText
        feedbackImage = seekDirection == .forward ? Image(systemName: "goforward") : Image(systemName: "gobackward")

        print("[GestureManager] showVisualFeedback - feedbackText: \(feedbackText), direction: \(seekDirection)")

        // Optionally, if you want to remove the FeedbackView after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.feedbackID = nil
        }
    }

    // MARK: - Timer Management

    private func startTapDelayTimer() {
        invalidateTapDelayTimer()
        print("[GestureManager] startTapDelayTimer")
        tapDelayTimer = Timer.scheduledTimer(withTimeInterval: tapDelay, repeats: false) { [weak self] _ in
            self?.handleTapDelayTimerFired()
        }
    }

    private func handleTapDelayTimerFired() {
        print("[GestureManager] handleTapDelayTimerFired - gestureState: \(gestureState)")
        if gestureState == .singleTapPending {
            handleSingleTap()
            gestureState = .idle
            print("[GestureManager] State changed to idle")
        }
        invalidateTapDelayTimer()
    }

    private func invalidateTapDelayTimer() {
        print("[GestureManager] invalidateTapDelayTimer")
        tapDelayTimer?.invalidate()
        tapDelayTimer = nil
    }

    private func startMultipleTapResetTimer() {
        invalidateMultipleTapResetTimer()
        print("[GestureManager] startMultipleTapResetTimer")
        multipleTapResetTimer = Timer.scheduledTimer(withTimeInterval: multipleTapResetDelay, repeats: false) { [weak self] _ in
            self?.resetMultipleTapping()
        }
    }

    private func resetMultipleTapResetTimer() {
        print("[GestureManager] resetMultipleTapResetTimer")
        startMultipleTapResetTimer()
    }

    private func invalidateMultipleTapResetTimer() {
        print("[GestureManager] invalidateMultipleTapResetTimer")
        multipleTapResetTimer?.invalidate()
        multipleTapResetTimer = nil
    }

    // MARK: - State Reset

    private func resetMultipleTapping() {
        print("[GestureManager] resetMultipleTapping")
        gestureState = .idle
        resetAccumulatedInterval()
        invalidateMultipleTapResetTimer()
        initialTime = nil
        lastSeekDirection = nil
        // No need to hide feedback; it will be managed by the FeedbackView
    }
}
