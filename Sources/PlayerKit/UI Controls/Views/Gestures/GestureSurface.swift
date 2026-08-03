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
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        GeometryReader { proxy in
            let surface = SurfaceGeometry(
                size: proxy.size,
                insets: proxy.safeAreaInsets,
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

    private var skipSeconds: String {
        let value = manager.configuration.skipInterval
        return value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private var accessibilityHint: Text {
        if manager.isLocked() {
            return Text("Controls are locked. Use Unlock controls to make playback actions available.")
        }
        return Text(
            "Shows the playback controls. Playback speed is in the controls; seeking, volume, brightness and zoom are available in Actions when supported."
        )
    }

    var body: some View {
        let geometry = manager.resolvedGeometry(for: surface)

        GestureTouchHost(manager: manager, surface: surface, onWindow: onWindow)
            .accessibilityElement()
            .accessibilityLabel("Video")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(accessibilityHint)
            .accessibilityAction { manager.toggleControls() }
            .accessibilityActionIf(
                canSkip,
                named: Text("Skip forward \(skipSeconds) seconds")
            ) {
                manager.skipForward()
            }
            .accessibilityActionIf(
                canSkip,
                named: Text("Skip back \(skipSeconds) seconds")
            ) {
                manager.skipBackward()
            }
            .accessibilityActionIf(canTogglePlayback, named: Text("Play or pause")) {
                manager.togglePlayback()
            }
            .accessibilityActionIf(
                canZoom,
                named: manager.isZoomFilled
                    ? Text("Fit video to screen")
                    : Text("Fill screen")
            ) {
                manager.toggleZoom()
            }
            .gestureAdjustmentAccessibilityActions(manager: manager, geometry: geometry)
            // Never `.accessibilityDirectTouch`: at full-screen size it
            // silences VoiceOver across the whole player, chrome included.
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
