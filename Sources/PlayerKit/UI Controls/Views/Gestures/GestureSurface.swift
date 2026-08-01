import SwiftUI

/// Replaces `GestureView`.
///
/// It holds **no** gesture state and observes nothing that changes at touch
/// rate: `manager` is a plain `let`, not an `@ObservedObject`. Everything that
/// updates while a finger is down is behind a leaf view with its own model, so a
/// 120Hz drag invalidates a capsule and a rail rather than the view that sits
/// under the entire player.
struct GestureSurface: View {

    let manager: GestureManager

    var body: some View {
        GeometryReader { proxy in
            let surface = SurfaceGeometry(size: proxy.size, insets: proxy.safeAreaInsets)
            let geometry = manager.resolvedGeometry(for: surface)

            ZStack {
                GestureTouchHost(
                    manager: manager,
                    surface: surface,
                    onWindow: { manager.attachWindow($0) }
                )
                .accessibilityElement()
                .accessibilityLabel("Video")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Shows the playback controls. More actions are available in the rotor.")
                .accessibilityAction { manager.toggleControls() }
                .accessibilityAction(named: Text("Skip forward 10 seconds")) { manager.skipForward() }
                .accessibilityAction(named: Text("Skip back 10 seconds")) { manager.skipBackward() }
                .accessibilityAction(named: Text("Play or pause")) { manager.togglePlayback() }
                .accessibilityAction(named: Text("Fill screen")) { manager.toggleZoom() }
                // Never `.accessibilityDirectTouch`: at full-screen size it
                // silences VoiceOver across the whole player, chrome included.

                GestureAccessibilityProxies(manager: manager, geometry: geometry)

                GestureScrimView(model: manager.hudModel)

                SeekOverlayHost(manager: manager, size: proxy.size)

                GestureRailAffordanceView(
                    geometry: geometry,
                    isVisible: manager.showsRestingAffordance
                )

                GestureHUDView(model: manager.hudModel, geometry: geometry)

                GestureCoachView(model: manager.coach, geometry: geometry)
            }
        }
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
                DoubleTapSeekOverlayView(state: overlay, size: size)
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
