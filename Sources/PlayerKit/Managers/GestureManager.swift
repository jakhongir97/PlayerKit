import SwiftUI
import Combine
#if os(iOS)
import AVFoundation
import MediaPlayer
#endif

public class GestureManager: ObservableObject {
    // MARK: - Published Properties
    @Published var visualFeedback: String?
    @Published var feedbackImage: Image?
    @Published var feedbackID: UUID? // Use an identifier to trigger FeedbackView
    @Published var isMultipleTapping: Bool = false
    
    // MARK: - Callback Closures
    var onSeek: ((_ newTime: Double) -> Void)?
    var onToggleControls: (() -> Void)?
    var onZoom: ((_ scale: CGFloat) -> Void)?
    var isLockedProvider: (() -> Bool)?
    var currentTimeProvider: (() -> Double)?
    /// The window a double-tap skip may land in.
    ///
    /// This used to be a `durationProvider`, which made live streams jump to
    /// the start: `duration` is 0 for live/DVR HLS, so clamping with
    /// `min(duration, …)` clamped every skip to zero. The seekable range is
    /// `0...duration` for VOD and the DVR window for live, so one provider
    /// serves both. `nil` means there is nothing to seek within, and the skip
    /// is dropped rather than sent to an arbitrary position.
    var seekableRangeProvider: (() -> ClosedRange<Double>?)?
    var onControlsVisibilityChange: ((Bool) -> Void)?
    
    // MARK: - Private Properties
    private var accumulatedInterval: Double = 0.0
    private var seekDirection: SeekDirection = .forward
    private var lastSeekDirection: SeekDirection?
    private var gestureState: GestureStates = .idle
    private var isRightSide: Bool = true
    private var tapDelayTimer: Timer?
    private var multipleTapResetTimer: Timer?
    private var initialTime: Double?
    
    // MARK: - Volume and Brightness Properties
    #if os(iOS)
    private var initialBrightness: CGFloat = UIScreen.main.brightness
    private var initialVolume: Float = AVAudioSession.sharedInstance().outputVolume
    /// The device's brightness before PlayerKit first changed it, so it can be
    /// handed back on teardown. `nil` means we have never touched brightness.
    private var brightnessBeforePlayback: CGFloat?
    #else
    private var initialBrightness: CGFloat = 0.5
    private var initialVolume: Float = 0.5
    private var brightnessBeforePlayback: CGFloat?
    #endif
    private var volumeSensitivity: CGFloat = 0.01
    private var brightnessSensitivity: CGFloat = 0.01
    
    // Constants
    private let tapDelay = 0.3 // Delay to distinguish single tap
    private let multipleTapResetDelay = 0.6 // Delay to reset multiple tapping
    private let fastSeekBaseInterval: Double = 10.0 // Base seek interval
    
    // MARK: - System Volume Slider
    #if os(iOS)
    private lazy var systemVolumeSlider: UISlider = {
        let volumeView = MPVolumeView()
        return volumeView.subviews.compactMap { $0 as? UISlider }.first ?? UISlider()
    }()
    #endif
    
    // MARK: - Handle Vertical Swipe (Volume & Brightness)
    // Define screen regions for gestures
    private let leftRegionWidthRatio: CGFloat = 0.33 // Left 30% of the screen for volume
    private let rightRegionWidthRatio: CGFloat = 0.66 // Right 30% of the screen for brightness
    private let centerRegionTopRatio: CGFloat = 0.33 // Start of the center region (33% of height)
    private let centerRegionBottomRatio: CGFloat = 0.66 // End of the center region (66% of height)

    func handleVerticalSwipe(at location: CGPoint, translation: CGSize, in size: CGSize) {
        guard !isLocked() else { return }

        // Calculate screen boundaries for horizontal and vertical regions
        let leftRegionEndX = size.width * leftRegionWidthRatio
        let rightRegionStartX = size.width * rightRegionWidthRatio
        let centerRegionTopY = size.height * centerRegionTopRatio
        let centerRegionBottomY = size.height * centerRegionBottomRatio

        // Only respond to gestures in the center third of the screen’s height
        if location.y >= centerRegionTopY && location.y <= centerRegionBottomY {
            if location.x < leftRegionEndX {
                adjustVolume(translation: translation.height)
            } else if location.x > rightRegionStartX {
                adjustBrightness(translation: translation.height)
            }
            // Ignore gestures outside the center region (top and bottom thirds)
        }
    }
    
    // Adjust volume based on vertical drag gesture
    private func adjustVolume(translation: CGFloat) {
        #if os(iOS)
        let volumeDelta = Float(-translation) * Float(volumeSensitivity)
        let newVolume = max(0.0, min(1.0, initialVolume + volumeDelta))
        
        DispatchQueue.main.async {
            self.systemVolumeSlider.setValue(newVolume, animated: true)
            self.systemVolumeSlider.sendActions(for: .valueChanged)
        }
        #endif
    }
    
    // Adjust brightness based on vertical drag gesture
    private func adjustBrightness(translation: CGFloat) {
        #if os(iOS)
        // Remember the device's own brightness the first time we touch it so
        // restoreSystemBrightness() can hand it back. Screen brightness is a
        // system-wide setting: without this, dimming the player left the user's
        // whole device dim after they closed it.
        if brightnessBeforePlayback == nil {
            brightnessBeforePlayback = UIScreen.main.brightness
        }
        let brightnessDelta = -translation * brightnessSensitivity
        UIScreen.main.brightness = max(0.0, min(1.0, initialBrightness + brightnessDelta))
        #endif
    }

    /// Restores the screen brightness PlayerKit found before it first adjusted it.
    ///
    /// Called from `PlayerManager.tearDown()`; safe to call when the gesture was
    /// never used, in which case it does nothing.
    func restoreSystemBrightness() {
        #if os(iOS)
        guard let brightnessBeforePlayback else { return }
        UIScreen.main.brightness = brightnessBeforePlayback
        self.brightnessBeforePlayback = nil
        #endif
    }

    // Re-read the current volume/brightness so the next swipe starts from where
    // the system actually is, rather than from a baseline captured at init.
    func resetInitialStates() {
        #if os(iOS)
        initialVolume = AVAudioSession.sharedInstance().outputVolume
        initialBrightness = UIScreen.main.brightness
        #endif
    }
    
    // MARK: - Public Methods
    
    func handlePinch(scale: CGFloat) {
        guard !isLocked() else { return }
        onZoom?(scale)  // Trigger the zoom action
    }
    
    func handleTap(at location: CGPoint, in size: CGSize) {
        isRightSide = location.x > size.width / 2
        let direction: SeekDirection = isRightSide ? .forward : .backward
        
        switch gestureState {
        case .idle:
            gestureState = .singleTapPending
            startTapDelayTimer()
            
        case .singleTapPending:
            invalidateTapDelayTimer()
            gestureState = .multipleTapping
            if initialTime == nil { initialTime = currentTimeProvider?() }
            onControlsVisibilityChange?(false)
            lastSeekDirection = direction
            handleMultipleTap(direction: direction)
            startMultipleTapResetTimer()
            
        case .multipleTapping:
            if direction != lastSeekDirection {
                resetAccumulatedInterval()
                initialTime = currentTimeProvider?()
                lastSeekDirection = direction
            }
            handleMultipleTap(direction: direction)
            resetMultipleTapResetTimer()
        }
    }
    
    func feedbackPosition(in size: CGSize) -> CGFloat {
        isRightSide ? size.width * 0.75 : size.width * 0.25
    }
    
    // MARK: - Private Methods
    
    private func handleSingleTap() {
        onToggleControls?()
    }
    
    private func handleMultipleTap(direction: SeekDirection) {
        guard !isLocked() else { return }
        isMultipleTapping = true
        seekDirection = direction
        accumulatedInterval += fastSeekBaseInterval
        performSeek()
        showVisualFeedback()
    }
    
    private func resetAccumulatedInterval() {
        accumulatedInterval = 0.0
    }
    
    private func performSeek() {
        guard let initialTime,
              let seekableRange = seekableRangeProvider?() else { return }

        let offset = seekDirection == .forward ? accumulatedInterval : -accumulatedInterval
        let newTime = min(
            max(initialTime + offset, seekableRange.lowerBound),
            seekableRange.upperBound
        )
        onSeek?(newTime)
    }
    
    private func showVisualFeedback() {
        feedbackID = UUID() // Reset feedbackID to trigger FeedbackView animation
        
        visualFeedback = seekDirection == .forward ? "\(Int(accumulatedInterval))" : "\(Int(accumulatedInterval))"
        feedbackImage = seekDirection == .forward ? Image(systemName: "goforward.plus") : Image(systemName: "gobackward.minus")
        
        // Cancel hiding the feedback if another tap occurs within 1 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            if self?.gestureState == .idle { // Only hide if no more taps occur
                self?.feedbackID = nil
            }
        }
    }
    
    // MARK: - Timer Management
    
    private func startTapDelayTimer() {
        invalidateTapDelayTimer()
        tapDelayTimer = Timer.scheduledTimer(withTimeInterval: tapDelay, repeats: false) { [weak self] _ in
            self?.handleTapDelayTimerFired()
        }
    }
    
    private func handleTapDelayTimerFired() {
        if gestureState == .singleTapPending {
            handleSingleTap()
            gestureState = .idle
        }
        invalidateTapDelayTimer()
    }
    
    private func invalidateTapDelayTimer() {
        tapDelayTimer?.invalidate()
        tapDelayTimer = nil
    }
    
    private func startMultipleTapResetTimer() {
        invalidateMultipleTapResetTimer()
        multipleTapResetTimer = Timer.scheduledTimer(withTimeInterval: multipleTapResetDelay, repeats: false) { [weak self] _ in
            self?.resetMultipleTapping()
        }
    }
    
    private func resetMultipleTapResetTimer() {
        startMultipleTapResetTimer()
    }
    
    private func invalidateMultipleTapResetTimer() {
        multipleTapResetTimer?.invalidate()
        multipleTapResetTimer = nil
    }
    
    // MARK: - State Reset
    
    private func resetMultipleTapping() {
        isMultipleTapping = false
        gestureState = .idle
        resetAccumulatedInterval()
        invalidateMultipleTapResetTimer()
        initialTime = nil
        lastSeekDirection = nil
    }

    private func isLocked() -> Bool {
        isLockedProvider?() ?? false
    }
}
