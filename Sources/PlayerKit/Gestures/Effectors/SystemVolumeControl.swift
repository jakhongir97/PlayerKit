import Foundation

#if os(iOS) && !targetEnvironment(macCatalyst)
import AVFoundation
import MediaPlayer
import UIKit

/// Device playback volume. **Opt-in** — see `VolumeGestureTarget.system`.
///
/// The only supported way to write it is through a real, mounted `MPVolumeView`.
/// The old code skipped the mounting, which broke it twice over: an unmounted
/// view's slider has no registered targets, and iOS only suppresses its own
/// volume HUD while an `MPVolumeView` is actually in the hierarchy. So the write
/// went nowhere and the system drew its HUD over the video anyway.
///
/// Mounting rules that matter:
/// - offscreen at `(-4000, -4000)` and `alpha 0.0001`, **not** `isHidden` —
///   a hidden view does not suppress the HUD;
/// - laid out, so the slider subview actually exists;
/// - the slider is re-resolved on **every** write, because the subview set is
///   dynamic and a cached reference goes stale across route changes.
final class SystemVolumeControl: OutputLevelControlling {

    private let volumeView = MPVolumeView(
        frame: CGRect(x: -4000, y: -4000, width: 1, height: 1)
    )
    private var isMounted = false
    private var didLogMissingSlider = false
    private var observation: NSKeyValueObservation?

    var onExternalChange: ((Double) -> Void)?

    init() {
        volumeView.alpha = 0.0001
        volumeView.isUserInteractionEnabled = false
    }

    deinit {
        observation?.invalidate()
    }

    var availability: GestureAvailability {
        guard isMounted else { return .unavailable(.noSystemVolumeControl) }
        guard resolveSlider() != nil else {
            if !didLogMissingSlider {
                didLogMissingSlider = true
                PlayerKitLog.debug("Gestures", "MPVolumeView exposed no slider; system volume gesture unavailable.")
            }
            return .unavailable(.noSystemVolumeControl)
        }
        return .available
    }

    var isSystemWide: Bool { true }
    var writeQuantum: Double { 1.0 / 16.0 }

    func mount(in window: PKWindow?) {
        guard let window, volumeView.superview !== window else { return }
        volumeView.removeFromSuperview()
        window.addSubview(volumeView)
        window.sendSubviewToBack(volumeView)
        volumeView.layoutIfNeeded()
        isMounted = true
        startObservingSystemVolume()
    }

    func unmount() {
        observation?.invalidate()
        observation = nil
        volumeView.removeFromSuperview()
        isMounted = false
    }

    func readLevel() -> Double {
        Double(AVAudioSession.sharedInstance().outputVolume)
    }

    func setLevel(_ value: Double) {
        guard let slider = resolveSlider() else { return }
        // No `sendActions(for:)`: measured against a mounted view, the slider
        // has no targets PlayerKit owns, and the write itself is what MediaPlayer
        // observes.
        slider.setValue(Float(min(max(value, 0), 1)), animated: false)
    }

    func refreshBaseline() {}

    /// Nothing to hand back — the user's own volume is the value we leave behind.
    func relinquish(force: Bool) {}

    private func resolveSlider() -> UISlider? {
        volumeView.subviews.compactMap { $0 as? UISlider }.first
    }

    /// Keeps the rail honest when the hardware buttons or Control Centre move
    /// the volume between gestures.
    private func startObservingSystemVolume() {
        guard observation == nil else { return }
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let self, let value = change.newValue else { return }
            Task { @MainActor [weak self] in
                self?.onExternalChange?(Double(value))
            }
        }
    }
}

#endif
