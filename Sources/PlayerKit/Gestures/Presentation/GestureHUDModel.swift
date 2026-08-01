import Combine
import Foundation
import QuartzCore

/// The only object in the gesture layer that changes at touch rate, and it is
/// observed by exactly one leaf view.
///
/// That containment is the whole performance story. The previous design had the
/// gesture state on `GestureManager`, an `ObservableObject` that `GestureView`
/// observed wholesale, so a value that changes 120 times a second invalidated a
/// view that sits under the entire player.
final class GestureHUDModel: ObservableObject {

    @Published private(set) var hud: GestureHUD?
    /// The compositing scrim that carries the bottom quarter of the brightness
    /// range. Separate from `hud` because it outlives the readout.
    @Published private(set) var dimScrim: Double = 0

    /// Rails the coach is demonstrating.
    ///
    /// Separate from `hud` only because the walkthrough teaches both halves at
    /// once and `hud` is a single slot. They go through the same renderer, so
    /// the rail on screen during coaching **is** the shipping rail — there is no
    /// second drawing of the interface that can drift from the first.
    @Published private(set) var demoRails: [RailSide: GestureHUD] = [:]

    var dwell: TimeInterval = 0.70

    private let clock: GestureClock
    private var pending: GestureHUD?
    private var hasPending = false
    private var flushScheduled = false
    private var dwellToken: GestureCancellable?

    init(clock: GestureClock) {
        self.clock = clock
    }

    deinit {
        dwellToken?.cancel()
    }

    /// The only writer.
    ///
    /// Drops a write that changes nothing, and coalesces the rest to one flush
    /// per display frame via `RunLoop.main.perform(inModes: [.common])`.
    ///
    /// Explicitly *not* a Combine `.throttle(on: RunLoop.main)`: Combine's
    /// RunLoop scheduler enqueues in `.default` mode, so the HUD would freeze
    /// for the whole drag whenever the main run loop is in tracking mode — a
    /// host's paging carousel, an interactive-dismiss sheet — and then snap to
    /// its final value on lift. That is precisely the symptom this rework exists
    /// to remove, and it is the same reasoning the seek session timers already
    /// carried.
    func set(_ next: GestureHUD?) {
        dwellToken?.cancel()
        dwellToken = nil

        guard next != hud || hasPending else { return }
        pending = next
        hasPending = true
        scheduleFlush()
    }

    func setDemoRail(_ hud: GestureHUD?, for side: RailSide) {
        if let hud {
            guard demoRails[side] != hud else { return }
            demoRails[side] = hud
        } else {
            guard demoRails[side] != nil else { return }
            demoRails[side] = nil
        }
    }

    func clearDemoRails() {
        guard !demoRails.isEmpty else { return }
        demoRails.removeAll()
    }

    func setScrim(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        guard clamped != dimScrim else { return }
        dimScrim = clamped
    }

    /// Starts the linger after the finger lifts.
    func beginDwell() {
        dwellToken?.cancel()
        dwellToken = clock.schedule(after: dwell) { [weak self] in
            self?.clearImmediately()
        }
    }

    func clearImmediately() {
        dwellToken?.cancel()
        dwellToken = nil
        pending = nil
        hasPending = false
        if hud != nil { hud = nil }
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            self?.flush()
        }
    }

    private func flush() {
        flushScheduled = false
        guard hasPending else { return }
        hasPending = false
        let next = pending
        pending = nil
        guard next != hud else { return }
        hud = next
    }
}
