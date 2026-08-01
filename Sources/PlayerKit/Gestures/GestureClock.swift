import Foundation
import QuartzCore

protocol GestureCancellable: AnyObject {
    func cancel()
}

/// Time, injected.
///
/// Every deadline in this subsystem — the 0.28s double-tap window, the 0.75s
/// session timeout, the 0.45s speed hold, the 0.12s rail arm delay, the 0.70s
/// HUD dwell — goes through here, which is what makes them synchronously
/// testable instead of requiring an `XCTestExpectation` and a real wall-clock
/// wait per case.
protocol GestureClock: AnyObject {
    var now: TimeInterval { get }
    @discardableResult
    func schedule(after delay: TimeInterval, _ body: @escaping () -> Void) -> GestureCancellable
}

/// Production clock.
///
/// Timers are added to `RunLoop.main` in `.common` mode so a countdown keeps
/// ticking while another gesture is tracking, instead of stalling a session
/// open. That is the same reasoning the original `GestureManager.schedule(_:)`
/// carried, and it is load-bearing: the default mode stops during tracking.
final class RunLoopClock: GestureClock {

    var now: TimeInterval { CACurrentMediaTime() }

    @discardableResult
    func schedule(after delay: TimeInterval, _ body: @escaping () -> Void) -> GestureCancellable {
        let token = TimerToken()
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            body()
        }
        RunLoop.main.add(timer, forMode: .common)
        token.timer = timer
        return token
    }

    private final class TimerToken: GestureCancellable {
        var timer: Timer?
        func cancel() {
            timer?.invalidate()
            timer = nil
        }
        deinit { timer?.invalidate() }
    }
}

/// Test double. `advance(by:)` fires everything due, synchronously, in order.
final class TestClock: GestureClock {

    var now: TimeInterval = 0

    private var pending: [Scheduled] = []
    private var nextID = 0

    @discardableResult
    func schedule(after delay: TimeInterval, _ body: @escaping () -> Void) -> GestureCancellable {
        nextID += 1
        let scheduled = Scheduled(id: nextID, fireAt: now + delay, body: body, clock: self)
        pending.append(scheduled)
        return scheduled
    }

    /// Fires in deadline order, re-checking after each callback so a timer
    /// scheduled *by* a callback within the same window still runs.
    func advance(by interval: TimeInterval) {
        let target = now + interval
        while true {
            let due = pending
                .filter { !$0.isCancelled && $0.fireAt <= target }
                .sorted { $0.fireAt == $1.fireAt ? $0.id < $1.id : $0.fireAt < $1.fireAt }
            guard let next = due.first else { break }
            now = max(now, next.fireAt)
            pending.removeAll { $0 === next }
            next.body()
        }
        now = max(now, target)
        pending.removeAll { $0.isCancelled }
    }

    var pendingCount: Int { pending.filter { !$0.isCancelled }.count }

    fileprivate final class Scheduled: GestureCancellable {
        let id: Int
        let fireAt: TimeInterval
        let body: () -> Void
        private(set) var isCancelled = false
        private weak var clock: TestClock?

        init(id: Int, fireAt: TimeInterval, body: @escaping () -> Void, clock: TestClock) {
            self.id = id
            self.fireAt = fireAt
            self.body = body
            self.clock = clock
        }

        func cancel() {
            isCancelled = true
            clock?.pending.removeAll { $0 === self }
        }
    }
}
