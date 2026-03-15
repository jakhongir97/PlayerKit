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
                .accessibilityLabel("Playback position")
                .accessibilityValue(accessibilityValueText)
                .accessibilityHint(PlayerKitPlatform.isDesktop ? "Click or drag to seek through the media" : "Drag to seek through the media")
                .accessibilityIdentifier("player.timeline")
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

    private func formatTime(_ value: Double) -> String {
        guard value.isFinite else { return "nan" }
        return String(format: "%.3f", value)
    }

    private func debugLog(_ message: String) {
        print("[PlayerKit][PlaybackSliderView] \(message)")
    }
}
