import SwiftUI

struct PlaybackSliderView: View {
    @ObservedObject var playerManager: PlayerManager
    @State private var sliderValue: Double = 0
    @State private var isEditingSlider = false
    
    private var accessibilityValueText: String {
        let current = effectiveSliderValue.asTimeString(style: .positional)
        let total = playerManager.duration.asTimeString(style: .positional)
        return "\(current) of \(total)"
    }

    private var effectiveSliderValue: Double {
        isEditingSlider ? sliderValue : playerManager.currentTime
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
                    height: 45
                ) { editing in
                    playerManager.isSeeking = editing
                    isEditingSlider = editing
                    if editing {
                        sliderValue = playerManager.currentTime
                    } else {
                        playerManager.seek(to: sliderValue)
                    }
                }
                .frame(height: 45)
                .padding(.vertical)
                .padding(.horizontal, 5)
                .contentShape(Rectangle())
                .accessibilityLabel("Playback position")
                .accessibilityValue(accessibilityValueText)
                .accessibilityHint("Drag to seek through the media")
                .accessibilityIdentifier("player.timeline")
            }
            .frame(height: 50)
        }
        .onAppear {
            sliderValue = playerManager.currentTime
        }
        .onChange(of: playerManager.currentTime) { _, newValue in
            if !isEditingSlider {
                sliderValue = newValue
            }
        }
    }
}
