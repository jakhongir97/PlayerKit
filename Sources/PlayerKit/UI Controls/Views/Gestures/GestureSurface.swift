import SwiftUI
import Foundation

/// Replaces `GestureView`.
///
/// It holds **no** gesture state and observes nothing that changes at touch
/// rate: `manager` is a plain `let`, not an `@ObservedObject`. Everything that
/// updates while a finger is down is behind a leaf view with its own model, so a
/// 120Hz drag invalidates a capsule and a rail rather than the view that sits
/// under the entire player.
struct GestureSurface: View {

    let manager: GestureManager
    /// The surface is deliberately full-bleed — a swipe should work over the
    /// whole picture — which means its own `GeometryReader` reports *zero*
    /// safe-area insets. `GestureGeometry` already keeps its rails and its pan
    /// region clear of the insets it is given, so the rails were being drawn
    /// 32pt from the raw bezel: under the Dynamic Island in landscape and in
    /// the home-indicator band at the bottom. The host passes the real insets
    /// measured outside the full-bleed expansion.
    var safeAreaInsets: EdgeInsets?
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        GeometryReader { proxy in
            let surface = SurfaceGeometry(
                size: proxy.size,
                insets: safeAreaInsets ?? proxy.safeAreaInsets,
                layoutDirection: layoutDirection
            )
            let geometry = manager.resolvedGeometry(for: surface)

            ZStack {
                AccessibleGestureTouchHost(
                    manager: manager,
                    surface: surface,
                    onWindow: { manager.attachWindow($0) }
                )

                GestureScrimView(model: manager.hudModel)

                SeekOverlayHost(manager: manager, size: proxy.size)

                RestingAffordanceHost(manager: manager, surface: surface)

                GestureHUDView(model: manager.hudModel, geometry: geometry)

                GestureCoachView(model: manager.coach, geometry: geometry)
            }
        }
    }
}

/// A small observed leaf so configuration, lock and zoom changes update the
/// rotor without making the full gesture surface observe touch-rate HUD state.
private struct AccessibleGestureTouchHost: View {
    @ObservedObject var manager: GestureManager
    let surface: SurfaceGeometry
    let onWindow: (PKWindow?) -> Void

    private var canSkip: Bool {
        manager.configuration.isEnabled
            && !manager.isLocked()
            && manager.seekableRangeProvider?() != nil
    }

    private var canTogglePlayback: Bool {
        manager.configuration.isEnabled
            && manager.configuration.isTwoFingerPlayPauseEnabled
            && !manager.isLocked()
    }

    private var canZoom: Bool {
        manager.isZoomAvailable() && !manager.isLocked()
    }

    private var accessibilityHint: Text {
        if manager.isLocked() {
            return Text(manager.strings.lockedVideoHint)
        }
        return Text(manager.strings.videoControlsHint)
    }

    var body: some View {
        let geometry = manager.resolvedGeometry(for: surface)

        GestureTouchHost(manager: manager, surface: surface, onWindow: onWindow)
            .accessibilityElement()
            .accessibilityLabel(manager.strings.video)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(accessibilityHint)
            .accessibilityAction { manager.toggleControls() }
            .accessibilityActionIf(
                canSkip,
                named: Text(manager.strings.skipForwardSeconds(manager.configuration.skipInterval))
            ) {
                manager.skipForward()
            }
            .accessibilityActionIf(
                canSkip,
                named: Text(manager.strings.skipBackSeconds(manager.configuration.skipInterval))
            ) {
                manager.skipBackward()
            }
            .accessibilityActionIf(canTogglePlayback, named: Text(manager.strings.playOrPause)) {
                manager.togglePlayback()
            }
            .accessibilityActionIf(
                canZoom,
                named: manager.isZoomFilled
                    ? Text(manager.strings.fitVideoToScreen)
                    : Text(manager.strings.fillScreen)
            ) {
                manager.toggleZoom()
            }
            .gestureAdjustmentAccessibilityActions(manager: manager, geometry: geometry)
            // Never `.accessibilityDirectTouch`: at full-screen size it
            // silences VoiceOver across the whole player, chrome included.
    }
}

/// The resting rail affordance.
///
/// Its visibility depends on the chrome, the lock and the seek session, and
/// its *icons* depend on the capabilities — none of which the surface
/// observes. Reading either from the surface's body meant they were evaluated
/// once per geometry change and never again: the rails stayed up after the
/// chrome auto-hid, and on a fresh launch both sides wore the volume glyph,
/// because brightness only becomes available once the touch host lands in a
/// window — after the surface's first render — and nothing repainted. This
/// leaf observes the manager (which republishes on those transitions and
/// bumps `capabilitiesGeneration` when the rails' meaning changes) and
/// resolves the geometry itself, so it always draws current capabilities.
private struct RestingAffordanceHost: View {
    @ObservedObject var manager: GestureManager
    let surface: SurfaceGeometry

    var body: some View {
        // Reads capabilitiesGeneration so a capability change re-renders this
        // leaf even though the resolved geometry is computed, not observed.
        let _ = manager.capabilitiesGeneration
        GestureRailAffordanceView(
            geometry: manager.resolvedGeometry(for: surface),
            isVisible: manager.showsRestingAffordance
        )
    }
}

/// The brightness scrim.
///
/// A separate leaf so darkening the picture does not re-run the surface, and so
/// it can sit *under* the HUD but over the video.
private struct GestureScrimView: View {
    @ObservedObject var model: GestureHUDModel

    var body: some View {
        Color.black
            .opacity(model.dimScrim)
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// The double-tap skip indicator.
///
/// Observes the manager on its own so the per-tap overlay change invalidates
/// this view and nothing else.
private struct SeekOverlayHost: View {
    @ObservedObject var manager: GestureManager
    let size: CGSize

    var body: some View {
        ZStack {
            if let overlay = manager.seekOverlay {
                DoubleTapSeekOverlayView(state: overlay, size: size, strings: manager.strings)
                    // Identity per side, so turning around swaps one panel for
                    // the other in place. Sharing identity instead made SwiftUI
                    // animate the single overlay across the screen, dragging a
                    // half-faded "30 seconds" over the new "10 seconds".
                    .id(overlay.direction)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: manager.seekOverlay)
    }
}
