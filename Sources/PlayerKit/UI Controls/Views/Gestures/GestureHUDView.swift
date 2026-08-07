import SwiftUI

/// The feedback layer. Deliberately **materialless**.
///
/// `.ultraThinMaterial` and `glassEffect` sample the backdrop, which means they
/// re-composite at video frame rate for the entire life of the HUD, and they
/// offer no guaranteed contrast ratio: over a blown-out shot the readout is
/// white type on a near-white disc, which is exactly the frame where feedback
/// matters most. A flat tinted capsule costs one layer and reads on anything.
///
/// The family resemblance to the rest of the player's chrome is bought with the
/// shared type ramp, motion curve and haptic grammar instead of with the
/// material.
struct GestureHUDView: View {

    @ObservedObject var model: GestureHUDModel
    let geometry: GestureGeometry

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            ForEach(RailSide.allCases, id: \.self) { side in
                if let demo = model.demoRails[side] {
                    railView(demo, side: side)
                        .transition(transition(for: .rail(side)))
                }
            }

            if let hud = model.hud {
                switch hud.slot {
                case .rail(let side):
                    railView(hud, side: side)
                        .transition(transition(for: hud.slot))
                case .banner:
                    pill(hud)
                        .position(
                            x: geometry.size.width / 2,
                            // Hangs from the chrome's own top inset, so the
                            // banner lines up with the title bar instead of
                            // floating at its own distance from the edge.
                            y: max(
                                geometry.surface.insets.top,
                                PlayerChromeMetrics.contentInset(for: geometry.size.width)
                            ) + 28
                        )
                        .transition(transition(for: hud.slot))
                case .center:
                    pill(hud)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .transition(transition(for: hud.slot))
                }
            }
        }
        .animation(motion, value: model.hud)
        .animation(motion, value: model.demoRails)
        .allowsHitTesting(false)
        // The value is announced from the model via `GestureAnnouncer`, not from
        // a view that disappears after 0.7s.
        .accessibilityHidden(true)
    }

    // MARK: - Rail

    private func railView(_ hud: GestureHUD, side: RailSide) -> some View {
        let frame = geometry.railFrame(side)
        return VStack(spacing: 10) {
            Image(systemName: hud.symbol)
                .font(.title3)
                .foregroundColor(.white)

            track(hud, height: frame.height)

            Text(hud.primary)
                .font(.callout)
                .monospacedDigitsCompat()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundColor(.white)

            if let secondary = hud.secondary {
                Text(secondary)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: 96)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .background(capsuleBackground)
        .opacity(hud.isArmed ? 0.55 : 1)
        .position(x: frame.midX, y: geometry.size.height / 2)
    }

    private func track(_ hud: GestureHUD, height: CGFloat) -> some View {
        let fraction = min(max(hud.fraction ?? 0, 0), 1)
        return ZStack(alignment: .bottom) {
            Capsule()
                .fill(Color.white.opacity(0.22))
            Capsule()
                .fill(Color.white)
                .frame(height: max(height * CGFloat(fraction), fraction > 0 ? 3 : 0))
        }
        .frame(width: 6, height: height)
        .scaleEffect(x: hud.isPinned ? 1.35 : 1, y: 1, anchor: .center)
        .animation(motion, value: hud.isPinned)
    }

    // MARK: - Pill

    private func pill(_ hud: GestureHUD) -> some View {
        HStack(spacing: 8) {
            Image(systemName: hud.symbol)
                .font(.body)
            VStack(alignment: .leading, spacing: 1) {
                Text(hud.primary)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigitsCompat()
                if let secondary = hud.secondary {
                    Text(secondary)
                        .font(.caption)
                        .monospacedDigitsCompat()
                        .opacity(0.85)
                }
                if let tertiary = hud.tertiary {
                    Text(tertiary)
                        .font(.caption2)
                        .monospacedDigitsCompat()
                        .opacity(0.7)
                }
            }
        }
        .foregroundColor(.white)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(capsuleBackground)
        .dynamicTypeSizeCompat()
    }

    // MARK: - Chrome

    private var capsuleBackground: some View {
        Capsule()
            .fill(Color.black.opacity(contrast == .increased ? 0.62 : 0.42))
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
    }

    private var motion: Animation? {
        reduceMotion ? .easeInOut(duration: 0.18) : .easeOut(duration: 0.12)
    }

    /// The readout enters travelling the way the finger does, which is the
    /// cheapest possible way to tie the feedback to the gesture that caused it.
    private func transition(for slot: GestureHUD.Slot) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        switch slot {
        case .rail:
            return .opacity.combined(with: .move(edge: .bottom))
        case .banner:
            return .opacity.combined(with: .move(edge: .top))
        case .center:
            return .opacity
        }
    }
}

extension View {
    /// Caps growth so a HUD cannot swallow the video at accessibility sizes.
    @ViewBuilder
    func dynamicTypeSizeCompat() -> some View {
        if #available(iOS 15.0, macOS 12.0, *) {
            self.dynamicTypeSize(...DynamicTypeSize.accessibility2)
        } else {
            self
        }
    }
}
