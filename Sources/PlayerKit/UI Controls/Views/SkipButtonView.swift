import SwiftUI
import Foundation

/// A visible ±10s control.
///
/// It exists because the skip was previously reachable *only* by double tapping
/// the video, which put it out of reach of anyone using Switch Control or
/// VoiceOver — and a Switch Control user scanning the chrome benefits far more
/// from a real button than from a rotor action buried on the video element.
///
/// It calls the same `TapSeekMachine` path the double tap uses, so a button
/// press, a rotor action, a keyboard arrow and a gesture cannot drift apart:
/// one clamp, one overlay, one accumulated total.
@MainActor
struct SkipButtonView: View {
    @ObservedObject var playerManager: PlayerManager
    @ObservedObject private var gestureManager: GestureManager
    let direction: SeekDirection

    private var isForward: Bool { direction == .forward }
    private var interval: Double {
        let configured = gestureManager.configuration.skipInterval
        return configured.isFinite ? configured : 10
    }
    private var intervalLabel: String {
        playerManager.strings.skipIntervalValue(interval)
    }
    private var canSkip: Bool {
        gestureManager.configuration.isEnabled
            && !playerManager.isLocked
            && playerManager.seekableRange != nil
    }

    init(playerManager: PlayerManager, direction: SeekDirection) {
        self.playerManager = playerManager
        _gestureManager = ObservedObject(wrappedValue: playerManager.gestureManager)
        self.direction = direction
    }

    var body: some View {
        Button {
            isForward ? playerManager.skipForward() : playerManager.skipBackward()
        } label: {
            ZStack {
                Image(systemName: isForward ? "goforward" : "gobackward")
                    .font(.system(size: 24, weight: .medium))
                Text(intervalLabel)
                    .font(.caption2.bold().monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: 24)
            }
            .foregroundColor(.white)
            // 44×44 minimum target, per the HIG accessibility guidance.
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSkip)
        .accessibilityHidden(!canSkip)
        .accessibilityLabel(
            isForward
                ? Text(playerManager.strings.skipForwardSeconds(interval))
                : Text(playerManager.strings.skipBackSeconds(interval))
        )
        .accessibilityIdentifier(isForward ? "player.skipForward" : "player.skipBackward")
    }
}
