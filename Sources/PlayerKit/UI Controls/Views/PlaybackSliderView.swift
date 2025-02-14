import SwiftUI

struct PlaybackSliderView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        VStack {
            ZStack(alignment: .leading) {
                ModernProgressSlider(
                    value: Binding(
                        get: { playerManager.currentTime },
                        set: { newValue in
                            playerManager.seek(to: newValue)
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
                    height: 40
                ) { editing in
                    playerManager.isSeeking = editing
                }
                .frame(height: 40)
                .padding(.vertical)
                .padding(.horizontal, 5)
                .contentShape(Rectangle())
            }
            .frame(height: 44)
        }
    }
}

