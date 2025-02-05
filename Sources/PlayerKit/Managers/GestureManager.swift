import SwiftUI
import Combine
import MediaPlayer

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
    private var initialBrightness: CGFloat = UIScreen.main.brightness
    private var initialVolume: Float = AVAudioSession.sharedInstance().outputVolume
    private var volumeSensitivity: CGFloat = 0.01
    private var brightnessSensitivity: CGFloat = 0.01
    
    // Constants
    private let tapDelay = 0.3 // Delay to distinguish single tap
    private let multipleTapResetDelay = 0.6 // Delay to reset multiple tapping
    private let fastSeekBaseInterval: Double = 10.0 // Base seek interval
    
    // MARK: - System Volume Slider
    private lazy var systemVolumeSlider: UISlider = {
        let volumeView = MPVolumeView()
        return volumeView.subviews.compactMap { $0 as? UISlider }.first ?? UISlider()
    }()
    
    // MARK: - Handle Vertical Swipe (Volume & Brightness)
    // Define screen regions for gestures
    private let leftRegionWidthRatio: CGFloat = 0.33 // Left 30% of the screen for volume
    private let rightRegionWidthRatio: CGFloat = 0.66 // Right 30% of the screen for brightness
    private let centerRegionTopRatio: CGFloat = 0.33 // Start of the center region (33% of height)
    private let centerRegionBottomRatio: CGFloat = 0.66 // End of the center region (66% of height)

    func handleVerticalSwipe(at location: CGPoint, translation: CGSize, in size: CGSize) {
        guard !PlayerManager.shared.isLocked else { return }

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
        let volumeDelta = Float(-translation) * Float(volumeSensitivity)
        let newVolume = max(0.0, min(1.0, initialVolume + volumeDelta))
        
        DispatchQueue.main.async {
            self.systemVolumeSlider.setValue(newVolume, animated: true)
            self.systemVolumeSlider.sendActions(for: .valueChanged)
        }
    }
    
    // Adjust brightness based on vertical drag gesture
    private func adjustBrightness(translation: CGFloat) {
        let brightnessDelta = -translation * brightnessSensitivity
        UIScreen.main.brightness = max(0.0, min(1.0, initialBrightness + brightnessDelta))
    }
    
    // Reset volume/brightness to initial states when swipe ends
    func resetInitialStates() {
        initialVolume = AVAudioSession.sharedInstance().outputVolume
        initialBrightness = UIScreen.main.brightness
    }
    
    // MARK: - Public Methods
    
    func handlePinch(scale: CGFloat) {
        guard !PlayerManager.shared.isLocked else { return }
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
            if initialTime == nil { initialTime = PlayerManager.shared.currentPlayer?.currentTime }
            PlayerManager.shared.areControlsVisible = false
            lastSeekDirection = direction
            handleMultipleTap(direction: direction)
            startMultipleTapResetTimer()
            
        case .multipleTapping:
            if direction != lastSeekDirection {
                resetAccumulatedInterval()
                initialTime = PlayerManager.shared.currentPlayer?.currentTime
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
        guard !PlayerManager.shared.isLocked else { return }
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
        guard let currentPlayer = PlayerManager.shared.currentPlayer,
              let initialTime = initialTime else { return }
        
        let newTime = max(0, min(currentPlayer.duration, initialTime + (seekDirection == .forward ? accumulatedInterval : -accumulatedInterval)))
        PlayerManager.shared.seek(to: newTime)
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
}

