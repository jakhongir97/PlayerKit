import Foundation
import QuartzCore

#if canImport(UIKit)
import UIKit
typealias PKWindow = UIWindow
#elseif canImport(AppKit)
import AppKit
typealias PKWindow = NSWindow
#endif

/// Something with a 0…1 output level that a rail gesture can drive.
///
/// The seam exists so the rail controller is a pure value transform: volume,
/// brightness, a null control for an unavailable capability and a recording fake
/// all sit behind it, and none of them leak `AVAudioSession` or `UIScreen` into
/// the gesture logic.
protocol OutputLevelControlling: AnyObject {
    var availability: GestureAvailability { get }
    /// True when writing changes something outside this player. Drives whether
    /// the value has to be handed back on teardown.
    var isSystemWide: Bool { get }
    /// The smallest step worth writing. Writing finer than the control's own
    /// resolution is pure overhead.
    var writeQuantum: Double { get }

    /// **Always** the read-back value, never the last requested one, so a
    /// control that clamped or refused a write tells the truth about it.
    func readLevel() -> Double
    func setLevel(_ value: Double)
    /// Re-read whatever the system is at now, so the next gesture starts from
    /// there rather than from a baseline captured at init.
    func refreshBaseline()
    /// Hand back anything system-wide this control took ownership of.
    func relinquish(force: Bool)

    var onExternalChange: ((Double) -> Void)? { get set }
}

extension OutputLevelControlling {
    func refreshBaseline() {}
    func relinquish(force: Bool) {}
}

/// Frame-rate and quantum gate for writes.
///
/// A drag on a 120Hz display delivers events far faster than any of these
/// controls can usefully consume them: screen brightness is a system call and
/// system volume crosses a process boundary. Two stored values, no allocation,
/// no dispatch.
struct LevelWriteGate {
    let quantum: Double
    private var lastStep: Int = .min
    private var lastWrite: CFTimeInterval = 0

    init(quantum: Double) {
        self.quantum = max(quantum, 0.0001)
    }

    mutating func shouldWrite(_ value: Double, now: CFTimeInterval) -> Bool {
        let step = Int((value / quantum).rounded())
        guard step != lastStep else { return false }
        guard now - lastWrite >= 1.0 / 60.0 else { return false }
        lastStep = step
        lastWrite = now
        return true
    }

    mutating func reset() {
        lastStep = .min
        lastWrite = 0
    }
}

/// Stands in for a control this platform, backend or configuration does not
/// have.
///
/// It exists so the rest of the layer never has to hold an optional and never
/// silently no-ops: an unavailable control removes the capability, which removes
/// the rail, the resting affordance, the coach lesson and the accessibility
/// element together.
final class NullLevelControl: OutputLevelControlling {
    let reason: GestureUnavailableReason
    var onExternalChange: ((Double) -> Void)?

    init(reason: GestureUnavailableReason) {
        self.reason = reason
    }

    var availability: GestureAvailability { .unavailable(reason) }
    var isSystemWide: Bool { false }
    var writeQuantum: Double { 1.0 / 16.0 }
    func readLevel() -> Double { 0 }
    func setLevel(_ value: Double) {}
}
