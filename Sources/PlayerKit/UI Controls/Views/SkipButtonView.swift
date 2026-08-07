import SwiftUI
import Foundation

/// A visible ±10s control.
///
/// It exists because the skip was previously reachable *only* by double tapping
/// the video, which put it out of reach of anyone using Switch Control or
/// VoiceOver — and a Switch Control user scanning the chrome benefits far more
/// from a real button than from a rotor action buried on the video element.
///
/// It performs a plain, self-contained ±interval seek. The double tap runs its
/// own accumulating session with the on-video overlay; this button deliberately
/// does not join it, so a press never hides the chrome or starts a counter — it
/// just moves the playhead by one interval, like any transport button.
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

    private static let diameter = PlayerChromeMetrics.secondaryControlDiameter

    init(playerManager: PlayerManager, direction: SeekDirection) {
        self.playerManager = playerManager
        _gestureManager = ObservedObject(wrappedValue: playerManager.gestureManager)
        self.direction = direction
    }

    /// The numeral sits inside the circular-arrow glyph, and both are sized off
    /// the shared control diameter so this control matches play/pause and
    /// previous/next instead of being a bare glyph floating between glass discs.
    var body: some View {
        Button {
            isForward ? playerManager.skipForward() : playerManager.skipBackward()
        } label: {
            ZStack {
                Image(systemName: isForward ? "goforward" : "gobackward")
                    .font(
                        .system(
                            size: PlayerChromeTypography.glyphSize(for: Self.diameter),
                            weight: .semibold
                        )
                    )
                Text(intervalLabel)
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: Self.diameter * 0.42)
                    .offset(y: 1)
            }
            .foregroundColor(.white)
            .frame(width: Self.diameter, height: Self.diameter)
            .playerSurfaceShape(.circle)
            .playerGlass(.circle, appearance: playerManager.appearance)
            .playerControlEnabled(canSkip)
        }
        .buttonStyle(PlayerControlButtonStyle(hoverEnabled: canSkip))
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
