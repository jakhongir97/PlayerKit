import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
#endif

/// Picture brightness, in two segments.
///
/// Two coordinate systems live here and they are deliberately stored separately,
/// because conflating them is how the old code lost the user's brightness:
///
/// - **`logicalLevel`** is what the user is dragging: 0…1 of "how bright the
///   picture looks".
/// - **`lastWrittenHardware`** is what *we* last wrote to the panel. It exists so
///   `relinquish` can tell "nobody has touched this since we set it" from "the
///   user or auto-brightness took it back", and only restore in the first case.
///
/// The bottom quarter of the logical range does not lower the panel any further
/// than `hardwareFloor`; it fades a compositing scrim in instead. A panel driven
/// to 0.0 is unreadable *and* slow to come back, whereas a scrim over a dim
/// panel gives a genuinely usable dark-room range and costs one already-composited
/// layer.
final class ScreenBrightnessControl: OutputLevelControlling {

    /// Below this the panel stops going down and the scrim takes over.
    static let hardwareFloor: CGFloat = 0.08
    /// Where the scrim segment ends and the hardware segment begins.
    static let scrimSegmentEnd: Double = 0.25
    static let maximumScrim: Double = 0.60

    weak var window: PKWindow?
    var mode: PlayerKitBrightnessMode = .screen
    /// Pushed to the compositing scrim, 0…`maximumScrim`.
    var onDimScrim: ((Double) -> Void)?
    var onExternalChange: ((Double) -> Void)?

    private var logicalLevel: Double = 1.0
    private var lastWrittenHardware: CGFloat?
    private var hardwareBeforePlayback: CGFloat?

    var writeQuantum: Double { 1.0 / 64.0 }

    var isSystemWide: Bool { mode == .screen && hardwareIsWritable }

    var availability: GestureAvailability {
        switch mode {
        case .disabled:
            return .unavailable(.disabledByHost)
        case .overlayOnly:
            // A scrim needs nothing from the platform.
            return .available
        case .screen:
            #if os(iOS)
            guard window != nil else { return .unavailable(.notSupportedOnPlatform) }
            if isOnExternalDisplay { return .unavailable(.externalDisplay) }
            return .available
            #else
            // No public API sets display brightness on macOS. Reporting this
            // honestly is what makes both halves of a Mac window drive volume
            // instead of leaving half the picture inert.
            return .unavailable(.notSupportedOnPlatform)
            #endif
        }
    }

    // MARK: - Level

    func readLevel() -> Double {
        logicalLevel
    }

    func setLevel(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        logicalLevel = clamped

        let scrim: Double
        let hardware: CGFloat

        if clamped <= Self.scrimSegmentEnd {
            let t = Self.scrimSegmentEnd > 0 ? clamped / Self.scrimSegmentEnd : 1
            scrim = Self.maximumScrim * (1 - t)
            hardware = Self.hardwareFloor
        } else {
            scrim = 0
            let t = (clamped - Self.scrimSegmentEnd) / (1 - Self.scrimSegmentEnd)
            hardware = Self.hardwareFloor + CGFloat(t) * (1 - Self.hardwareFloor)
        }

        onDimScrim?(scrim)
        guard mode == .screen else { return }
        writeHardware(hardware)
    }

    /// Seeds the logical value from the panel, but **only** when we do not
    /// already own it.
    ///
    /// Re-seeding while we own the panel would fold our own scrim segment back
    /// in as if the user had set it, so a second swipe in a dim room would start
    /// from the floor rather than from where the first one left off.
    func refreshBaseline() {
        guard mode == .screen else { return }
        guard lastWrittenHardware == nil else { return }
        #if os(iOS)
        guard let current = currentHardware else { return }
        logicalLevel = Self.logicalValue(forHardware: current)
        #endif
    }

    static func logicalValue(forHardware hardware: CGFloat) -> Double {
        guard hardware > hardwareFloor else { return scrimSegmentEnd }
        let t = Double((hardware - hardwareFloor) / (1 - hardwareFloor))
        return scrimSegmentEnd + t * (1 - scrimSegmentEnd)
    }

    // MARK: - Ownership

    /// Restores the panel PlayerKit found before it first dimmed it.
    ///
    /// Screen brightness is system-wide: without this, dimming the player left
    /// the user's whole device dim after they closed it. The guard is the part
    /// that was missing — if the value has drifted from what we last wrote, then
    /// the user or auto-brightness has taken ownership since, and writing our
    /// old value back would be us overriding *them*.
    func relinquish(force: Bool) {
        onDimScrim?(0)
        #if os(iOS)
        defer {
            lastWrittenHardware = nil
            hardwareBeforePlayback = nil
        }
        guard let original = hardwareBeforePlayback else { return }
        guard mode == .screen else { return }
        if !force {
            guard let written = lastWrittenHardware, let current = currentHardware else { return }
            guard abs(current - written) < 0.01 else { return }
        }
        applyHardware(original)
        #endif
    }

    // MARK: - Platform

    private var hardwareIsWritable: Bool {
        #if os(iOS)
        return window != nil && !isOnExternalDisplay
        #else
        return false
        #endif
    }

    #if os(iOS)
    /// A window scene created for an external display must never have its
    /// brightness driven — and `UISceneSession.Role` answers that without
    /// touching the deprecated `UIScreen.main`.
    private var isOnExternalDisplay: Bool {
        guard let scene = window?.windowScene else { return false }
        return scene.session.role == .windowExternalDisplay
    }

    private var screen: UIScreen? {
        window?.windowScene?.screen
    }

    private var currentHardware: CGFloat? {
        screen?.brightness
    }
    #endif

    private func writeHardware(_ value: CGFloat) {
        #if os(iOS)
        guard hardwareIsWritable else { return }
        // Remember the device's own brightness the first time we touch it, so
        // `relinquish` has something to hand back.
        if hardwareBeforePlayback == nil {
            hardwareBeforePlayback = currentHardware
        }
        applyHardware(min(max(value, 0), 1))
        #endif
    }

    private func applyHardware(_ value: CGFloat) {
        #if os(iOS)
        screen?.brightness = value
        lastWrittenHardware = value
        #endif
    }
}
