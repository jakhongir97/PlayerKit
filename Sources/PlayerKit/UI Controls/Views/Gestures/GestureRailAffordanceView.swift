import SwiftUI

/// The resting affordance: a quiet track on each side that says "something
/// lives here" without saying anything else.
///
/// Shown only while the chrome is already up, so it belongs to a moment the user
/// is already looking at the interface rather than the video. It draws
/// **nothing** on a side whose capability is unavailable — an affordance that
/// advertises a gesture the platform cannot perform is worse than no affordance,
/// because it converts "I did not know" into "it is broken".
struct GestureRailAffordanceView: View {

    let geometry: GestureGeometry
    let isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(RailSide.allCases, id: \.self) { side in
                if let kind = geometry.kind(forSide: side),
                   geometry.capabilities.availability(of: kind).isAvailable {
                    affordance(for: side, kind: kind)
                }
            }
        }
        .opacity(isVisible ? 1 : 0)
        // Its own scoped animation, never the root stack's, so a rail fading in
        // cannot drag the seek overlay or the HUD into the same transition.
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.28), value: isVisible)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func affordance(for side: RailSide, kind: GestureKind) -> some View {
        let frame = geometry.railFrame(side)
        return VStack(spacing: 8) {
            Image(systemName: kind == .brightness ? "sun.max" : "speaker.wave.2")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.24))
            Capsule()
                .fill(Color.white.opacity(0.30))
                .frame(width: 4, height: 96)
        }
        .position(x: frame.midX, y: geometry.size.height / 2)
    }
}
