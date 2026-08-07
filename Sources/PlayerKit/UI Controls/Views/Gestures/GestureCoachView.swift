import SwiftUI

/// The coached walkthrough, drawn over the live rail it is teaching.
///
/// What this view deliberately does **not** contain: a scrim, a dimmed
/// background, a modal, a "Got it" button, or anything that pauses playback. The
/// rail itself is drawn by `GestureHUDView` from real `GestureHUD` values the
/// coach pushes into the real model, so the thing on screen during the lesson is
/// the shipping control, not an illustration of it.
///
/// The hint styling is intentionally *not* the chrome's styling — no glass, no
/// capsule buttons — because the documented failure mode for coach marks is
/// people tapping the hint believing it is real UI.
struct GestureCoachView: View {

    @ObservedObject var model: GestureCoachModel
    let geometry: GestureGeometry

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sizeCategory) private var sizeCategory

    var body: some View {
        ZStack {
            switch model.stage {
            case .walkthrough(let sides, let staticPresentation):
                walkthrough(sides: sides, isStatic: staticPresentation || reduceMotion)
            case .nudge(let side, let text):
                nudge(side: side, text: text)
            case .none:
                EmptyView()
            }
        }
        .animation(.easeOut(duration: 0.25), value: model.stage)
    }

    // MARK: - Walkthrough

    private func walkthrough(sides: [RailSide], isStatic: Bool) -> some View {
        ZStack {
            ForEach(sides, id: \.self) { side in
                lesson(side: side, sides: sides, isStatic: isStatic)
            }
            skipButton
        }
        .transition(.opacity)
    }

    private func lesson(side: RailSide, sides: [RailSide], isStatic: Bool) -> some View {
        let frame = geometry.railFrame(side)
        // Anchored just inside its own half, beside the rail it describes.
        let x = side == .leading
            ? min(frame.maxX + 86, geometry.size.width * 0.44)
            : max(frame.minX - 86, geometry.size.width * 0.56)

        return VStack(spacing: 10) {
            if isStatic {
                staticHint
            } else {
                GhostFingerView()
            }
            Text(model.copy(for: side, sides: sides, isAccessibilitySize: isAccessibilitySize))
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                .frame(maxWidth: 168)
        }
        .dynamicTypeSizeCompat()
        .position(x: x, y: geometry.size.height / 2)
        .allowsHitTesting(false)
    }

    /// Reduce Motion replaces the travelling ghost with a static pair of
    /// chevrons: same information, no loop, no travel, no spring.
    private var staticHint: some View {
        VStack(spacing: 2) {
            Image(systemName: "chevron.up")
            Image(systemName: "chevron.down")
        }
        .font(.title3.weight(.semibold))
        .foregroundColor(.white.opacity(0.85))
    }

    /// The only tappable thing the coach adds.
    private var skipButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    model.dismiss(.skipped)
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(model.strings.skipGestureTips)
            }
            Spacer()
        }
        // The chrome's inset, not a private 8pt: the dismiss control used to
        // hug the corner tighter than anything else on screen.
        .padding(
            .top,
            max(
                geometry.surface.insets.top,
                PlayerChromeMetrics.contentInset(for: geometry.size.width)
            )
        )
        .padding(
            .trailing,
            max(
                geometry.surface.insets.trailing,
                PlayerChromeMetrics.contentInset(for: geometry.size.width)
            )
        )
    }

    // MARK: - Nudge

    private func nudge(side: RailSide, text: String) -> some View {
        let frame = geometry.railFrame(side)
        let x = side == .leading
            ? min(frame.maxX + 90, geometry.size.width * 0.45)
            : max(frame.minX - 90, geometry.size.width * 0.55)
        return Text(text)
            .font(.footnote.weight(.medium))
            .multilineTextAlignment(.center)
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
            .frame(maxWidth: 180)
            .dynamicTypeSizeCompat()
            .position(x: x, y: geometry.size.height / 2)
            .transition(.opacity)
            .allowsHitTesting(false)
    }

    /// Read from the environment rather than from `UIApplication.shared`, which
    /// is unavailable in an app extension — a package cannot assume it is
    /// hosted by a full application.
    private var isAccessibilitySize: Bool {
        sizeCategory.isAccessibilityCategory
    }
}

/// A fingertip travelling up and back down, three times.
///
/// It is a *ghost* — translucent, ringed, obviously not a control — because the
/// one thing worse than an undiscoverable gesture is a hint the user tries to
/// press.
private struct GhostFingerView: View {
    @State private var offset: CGFloat = 0

    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.55))
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 1))
            .frame(width: 44, height: 44)
            .offset(y: offset)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: GestureCoachModel.ghostLoopDuration / 2)
                    .repeatCount(GestureCoachModel.ghostLoopCount * 2, autoreverses: true)
                ) {
                    offset = -90
                }
            }
    }
}
