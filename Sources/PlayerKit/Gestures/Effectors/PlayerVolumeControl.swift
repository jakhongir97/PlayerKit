import Foundation

#if os(iOS)
import AVFoundation
#endif

/// Volume that routes to the **backend**, not to the device.
///
/// This is the default target, and it replaces a mechanism that was measurably
/// dead: the old code built an `MPVolumeView`, pulled its private `UISlider` out
/// of the subview tree and called `setValue` + `sendActions` on it — while never
/// adding the view to any hierarchy. An unmounted `MPVolumeView` has no
/// registered targets, so `sendActions` reached nothing, and because the view
/// was not on screen iOS also kept drawing its *own* volume HUD over the video.
/// The user saw the system HUD, assumed the player had done it, and got no
/// player-side feedback at all.
///
/// Writing the backend's own level is scoped to this player, needs no private
/// view, and cannot leave the device quieter than the user found it.
@MainActor
final class PlayerVolumeControl: OutputLevelControlling {

    var backendProvider: (() -> PlayerVolumeControlling?)?
    /// The device's playback volume, used only to explain a rail that will not
    /// move because the *hardware* is down, not the player.
    var systemVolumeProbe: (() -> Float)?
    var onExternalChange: ((Double) -> Void)?

    var availability: GestureAvailability {
        backendProvider?() != nil ? .available : .unavailable(.noBackend)
    }

    var isSystemWide: Bool { false }
    var writeQuantum: Double { 1.0 / 16.0 }

    func readLevel() -> Double {
        guard let backend = backendProvider?() else { return 1 }
        return Double(backend.outputVolume)
    }

    func setLevel(_ value: Double) {
        guard value.isFinite, let backend = backendProvider?() else { return }
        backend.setOutputVolume(Float(min(max(value, 0), 1)))
    }

    /// True when the player is already at unity but the device itself is turned
    /// down, i.e. the rail is at the top and the user still cannot hear
    /// anything. The HUD says so rather than showing a full rail that does
    /// nothing.
    var isLimitedByDeviceVolume: Bool {
        guard let probe = systemVolumeProbe else { return false }
        return readLevel() >= 0.99 && probe() < 0.95
    }
}

#if os(iOS)
extension PlayerVolumeControl {
    static func systemOutputVolume() -> Float {
        AVAudioSession.sharedInstance().outputVolume
    }
}
#endif
