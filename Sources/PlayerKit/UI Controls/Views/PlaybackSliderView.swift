import SwiftUI

struct PlaybackSliderView: View {
    @ObservedObject var playerManager: PlayerManager
    @State private var sliderValue: Double = 0
    @State private var isEditingSlider = false
    @State private var pendingSeekValue: Double?

    private var sliderHeight: CGFloat {
        PlayerKitPlatform.isDesktop ? 36 : 45
    }

    private var horizontalInset: CGFloat {
        PlayerKitPlatform.isDesktop ? 8 : 5
    }
    
    private var accessibilityValueText: String {
        let current = effectiveSliderValue.asTimeString(style: .positional)
        let total = playerManager.duration.asTimeString(style: .positional)
        return "\(current) of \(total)"
    }

    private var effectiveSliderValue: Double {
        if isEditingSlider {
            return sliderValue
        }
        if let pendingSeekValue {
            return pendingSeekValue
        }
        return playerManager.currentTime
    }

    var body: some View {
        VStack {
            ZStack(alignment: .leading) {
                ModernProgressSlider(
                    value: Binding(
                        get: { effectiveSliderValue },
                        set: { newValue in
                            sliderValue = newValue
                        }
                    ),
                    bufferedValue: Binding( // New binding for buffered progress
                        get: { playerManager.bufferedDuration },
                        set: { _ in } // No need to set this manually
                    ),
                    inRange: 0...max(playerManager.duration, 0.01),
                    activeFillColor: .white,
                    fillColor: .white.opacity(0.5),
                    emptyColor: .white.opacity(0.3),
                    bufferedColor: .white.opacity(0.1), // Light gray for buffered progress
                    height: sliderHeight
                ) { editing in
                    playerManager.isSeeking = editing
                    isEditingSlider = editing
                    if editing {
                        debugLog(
                            "Begin scrubbing current=\(formatTime(playerManager.currentTime)) " +
                            "isPlaying=\(playerManager.isPlaying)"
                        )
                        pendingSeekValue = nil
                        playerManager.userInteracted()
                    } else {
                        let targetValue = sliderValue
                        debugLog(
                            "End scrubbing target=\(formatTime(targetValue)) " +
                            "current=\(formatTime(playerManager.currentTime)) " +
                            "shouldResume=\(playerManager.isPlaying)"
                        )
                        pendingSeekValue = targetValue
                        playerManager.userInteracted()
                        playerManager.seek(to: targetValue) { success in
                            DispatchQueue.main.async {
                                debugLog(
                                    "Seek completion success=\(success) " +
                                    "target=\(formatTime(targetValue)) " +
                                    "current=\(formatTime(playerManager.currentTime)) " +
                                    "isPlaying=\(playerManager.isPlaying)"
                                )
                                pendingSeekValue = nil
                                if !success {
                                    sliderValue = playerManager.currentTime
                                }
                            }
                        }
                    }
                }
                .frame(height: sliderHeight)
                .padding(.vertical)
                .padding(.horizontal, horizontalInset)
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Playback position")
                .accessibilityValue(accessibilityValueText)
                .accessibilityHint(PlayerKitPlatform.isDesktop ? "Click or drag to seek through the media" : "Drag to seek through the media")
                .accessibilityIdentifier("player.timeline")
                // The slider previously exposed a label and a value but no way
                // to change them, so VoiceOver users could read the playhead
                // but could not seek at all. Attaching an adjustable action is
                // what makes swipe-up/swipe-down scrub.
                .accessibilityAdjustableAction { direction in
                    adjustPlaybackPosition(direction)
                }
            }
            .frame(height: PlayerKitPlatform.isDesktop ? 42 : 50)
        }
        .onAppear {
            sliderValue = playerManager.currentTime
        }
        .compatOnChange(of: playerManager.currentTime) { newValue in
            if !isEditingSlider {
                sliderValue = newValue
                if let pendingSeekValue, abs(pendingSeekValue - newValue) < 0.75 {
                    self.pendingSeekValue = nil
                }
            }
        }
    }

    /// Seeks by a fixed step in response to a VoiceOver adjust gesture.
    ///
    /// The step scales with duration so a swipe is useful on both a 30-second
    /// clip and a three-hour film, with a 15-second floor to match the
    /// scrub-button convention.
    private func adjustPlaybackPosition(_ direction: AccessibilityAdjustmentDirection) {
        let duration = playerManager.duration
        guard duration > 0 else { return }

        let step = max(duration / 20, 15)
        let delta: Double
        switch direction {
        case .increment:
            delta = step
        case .decrement:
            delta = -step
        @unknown default:
            return
        }

        let target = min(max(effectiveSliderValue + delta, 0), duration)
        sliderValue = target
        pendingSeekValue = target
        playerManager.userInteracted()
        playerManager.seek(to: target) { _ in }
    }

    private func formatTime(_ value: Double) -> String {
        guard value.isFinite else { return "nan" }
        return String(format: "%.3f", value)
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        PlayerKitLog.debug("PlaybackSliderView", message())
    }
}
