import SwiftUI

@MainActor
struct PlaybackSliderView: View {
    @ObservedObject var playerManager: PlayerManager
    #if os(iOS)
    @ObservedObject var thumbnailPreviewController: WebVTTThumbnailPreviewController
    #endif
    @State private var sliderValue: Double = 0
    @State private var isEditingSlider = false
    @State private var pendingSeekValue: Double?
    @State private var seekRequestID = 0

    private var sliderHeight: CGFloat {
        PlayerKitPlatform.isDesktop ? 44 : 52
    }

    private var horizontalInset: CGFloat {
        PlayerChromeMetrics.spacingXS
    }
    
    private var accessibilityValueText: String {
        let current = effectiveSliderValue.asTimeString(style: .positional)
        // The end of the seekable window, not `duration`, which is 0 on live
        // and made VoiceOver announce every position as "… of 00:00".
        let total = (seekableRange?.upperBound ?? playerManager.duration)
            .asTimeString(style: .positional)
        return playerManager.strings.playbackPositionValue(current, total)
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

    /// The window the scrubber may move within, or `nil` when there is none.
    ///
    /// This used to be `0...max(duration, 0.01)`. `duration` is 0 for live/DVR
    /// HLS, so on a live stream the scrubber's range collapsed to `0...0.01`
    /// and every drag resolved to the same position. `PlayerManager` already
    /// clamps seeks into this range, so reading it here is what makes the
    /// control agree with what a seek will actually do.
    private var seekableRange: ClosedRange<Double>? {
        playerManager.seekableRange
    }

    /// A range for the slider geometry even when nothing is seekable.
    ///
    /// Matches the old degenerate range so an unseekable timeline lays out
    /// exactly as it did before, rather than the row appearing and
    /// disappearing as `duration` resolves. Interaction is disabled instead.
    private var sliderRange: ClosedRange<Double> {
        seekableRange ?? 0...0.01
    }

    var body: some View {
        VStack {
            ZStack(alignment: .leading) {
                ModernProgressSlider(
                    value: Binding(
                        get: { effectiveSliderValue },
                        set: { newValue in
                            sliderValue = newValue
                            #if os(iOS)
                            if isEditingSlider {
                                thumbnailPreviewController.update(to: newValue)
                            }
                            #endif
                        }
                    ),
                    bufferedValue: Binding( // New binding for buffered progress
                        get: { playerManager.bufferedDuration },
                        set: { _ in } // No need to set this manually
                    ),
                    inRange: sliderRange,
                    // The played portion carries the host's accent — one of
                    // only two places a brand appears in the chrome. It used to
                    // be white at 50% opacity at rest and only reached full
                    // white while being dragged, so the resting scrubber never
                    // showed a confident "you are here".
                    activeFillColor: playerManager.appearance.accent,
                    fillColor: playerManager.appearance.accent,
                    // Buffered was white at 10% over an empty track at 30% —
                    // *darker* than the track it was meant to stand out from,
                    // which is why the buffer bar was invisible.
                    emptyColor: .white.opacity(0.24),
                    bufferedColor: .white.opacity(0.45),
                    height: sliderHeight
                ) { editing in
                    #if os(iOS)
                    if editing {
                        thumbnailPreviewController.begin(at: sliderValue)
                    } else {
                        thumbnailPreviewController.end()
                    }
                    #endif
                    playerManager.isSeeking = editing
                    isEditingSlider = editing
                    if editing {
                        debugLog(
                            "Begin scrubbing current=\(formatTime(playerManager.currentTime)) " +
                            "isPlaying=\(playerManager.isPlaying)"
                        )
                        invalidatePendingSeek()
                        playerManager.userInteracted()
                    } else {
                        let targetValue = sliderValue
                        debugLog(
                            "End scrubbing target=\(formatTime(targetValue)) " +
                            "current=\(formatTime(playerManager.currentTime)) " +
                            "shouldResume=\(playerManager.isPlaying)"
                        )
                        playerManager.userInteracted()
                        performSeek(to: targetValue)
                    }
                } onEditingCancelled: {
                    #if os(iOS)
                    thumbnailPreviewController.end()
                    #endif
                    playerManager.isSeeking = false
                    isEditingSlider = false
                    invalidatePendingSeek()
                    sliderValue = playerManager.currentTime
                }
                .frame(minHeight: sliderHeight)
                .padding(.horizontal, horizontalInset)
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(playerManager.strings.playbackPosition)
                .accessibilityValue(accessibilityValueText)
                #if os(macOS)
                .accessibilityHint("Click or drag to seek through the media")
                #else
                .accessibilityHint(playerManager.strings.seekThroughMediaHint)
                #endif
                .accessibilityIdentifier("player.timeline")
                .accessibilityHidden(seekableRange == nil)
                // The slider previously exposed a label and a value but no way
                // to change them, so VoiceOver users could read the playhead
                // but could not seek at all. Attaching an adjustable action is
                // what makes swipe-up/swipe-down scrub.
                .accessibilityAdjustableAction { direction in
                    adjustPlaybackPosition(direction)
                }
            }
            // One height for the row, declared once. It used to be framed at
            // 36/45 inside `ModernProgressSlider`, re-framed at 36/45 here,
            // given an unlabelled `.padding(.vertical)` and then clamped again
            // at 42/50 — four numbers for one row, none of which matched the
            // ~56pt the content actually wanted, so the scrubber's hit area
            // overhung the button bar beneath it.
            .frame(minHeight: sliderHeight)
            // Nothing to scrub within: keep the row so the layout does not
            // jump while `duration` resolves, but do not offer a control that
            // cannot move the playhead.
            .disabled(seekableRange == nil)
        }
        .onAppear {
            sliderValue = playerManager.currentTime
        }
        .compatOnChange(of: playerManager.currentTime) { newValue in
            if !isEditingSlider {
                sliderValue = newValue
                if let pendingSeekValue, abs(pendingSeekValue - newValue) < 0.75 {
                    invalidatePendingSeek()
                }
            }
        }
        .compatOnChange(of: seekableRange) { range in
            if range == nil, isEditingSlider {
                #if os(iOS)
                thumbnailPreviewController.end()
                #endif
                playerManager.isSeeking = false
                isEditingSlider = false
                invalidatePendingSeek()
                sliderValue = playerManager.currentTime
            }
        }
    }

    /// Seeks by a fixed step in response to a VoiceOver adjust gesture.
    ///
    /// The step scales with the seekable window so a swipe is useful on both a
    /// 30-second clip and a three-hour film, with a 15-second floor to match
    /// the scrub-button convention. It used to scale with `duration` and bail
    /// on `duration > 0`, which made VoiceOver scrubbing dead on live for the
    /// same reason the visual scrubber was.
    private func adjustPlaybackPosition(_ direction: AccessibilityAdjustmentDirection) {
        guard let seekableRange else { return }
        let span = seekableRange.upperBound - seekableRange.lowerBound
        guard span > 0 else { return }

        let step = max(span / 20, 15)
        let delta: Double
        switch direction {
        case .increment:
            delta = step
        case .decrement:
            delta = -step
        @unknown default:
            return
        }

        let target = min(
            max(effectiveSliderValue + delta, seekableRange.lowerBound),
            seekableRange.upperBound
        )
        sliderValue = target
        playerManager.userInteracted()
        performSeek(to: target)
    }

    private func performSeek(to target: Double) {
        seekRequestID &+= 1
        let requestID = seekRequestID
        pendingSeekValue = target
        playerManager.seek(to: target) { success in
            DispatchQueue.main.async {
                guard requestID == seekRequestID else { return }
                debugLog(
                    "Seek completion success=\(success) " +
                    "target=\(formatTime(target)) " +
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

    private func invalidatePendingSeek() {
        seekRequestID &+= 1
        pendingSeekValue = nil
    }

    private func formatTime(_ value: Double) -> String {
        guard value.isFinite else { return "nan" }
        return String(format: "%.3f", value)
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        PlayerKitLog.debug("PlaybackSliderView", message())
    }
}
