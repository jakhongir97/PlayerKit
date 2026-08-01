import SwiftUI

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
struct SkipButtonView: View {
    @ObservedObject var playerManager: PlayerManager
    let direction: SeekDirection

    private var isForward: Bool { direction == .forward }

    var body: some View {
        Button {
            isForward ? playerManager.skipForward() : playerManager.skipBackward()
        } label: {
            Image(systemName: isForward ? "goforward.10" : "gobackward.10")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.white)
                // 44×44 minimum target, per the HIG accessibility guidance.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isForward ? "Skip forward 10 seconds" : "Skip back 10 seconds")
        .accessibilityIdentifier(isForward ? "player.skipForward" : "player.skipBackward")
    }
}
