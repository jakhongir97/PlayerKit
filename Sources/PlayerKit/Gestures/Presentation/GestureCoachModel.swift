import Combine
import Foundation

/// The first-run coached walkthrough.
///
/// The design constraint that shaped everything here: **no scrim, no modal, no
/// button between the user and the video, and playback never pauses.** A
/// tutorial that stops the film to explain the film is the thing people
/// dismiss without reading. The whole interruption budget is under six seconds
/// and requires zero taps.
///
/// It teaches exactly two gestures — the two the user cannot see and cannot
/// guess — anchored inside the half each one belongs to, and it teaches them by
/// driving the *real* rail. If the user performs the gesture while it is on
/// screen, the demo drops out from under their finger and the rail goes live
/// with no visual discontinuity: the lesson completes by being done.
final class GestureCoachModel: ObservableObject {

    enum Stage: Equatable {
        case walkthrough(sides: [RailSide], reduceMotion: Bool)
        case nudge(side: RailSide, text: String)
    }

    enum DismissReason: Equatable {
        case timeout
        case skipped
        /// The user did the thing being taught.
        case performed
        case touched
        case suppressed
        case hostDisabled
    }

    // MARK: - Persistence

    enum DefaultsKey {
        /// An `Int`, not a `Bool`, so a future gesture change can bump
        /// `currentVersion` and re-coach exactly once.
        static let seenVersion = "PlayerKit.GestureCoach.SeenVersion"
        static let shownCount = "PlayerKit.GestureCoach.ShownCount"
        static let nudgeCount = "PlayerKit.GestureCoach.NudgeCount"
    }

    static let currentVersion = 1
    static let maximumPresentations = 2
    static let maximumNudges = 3

    // MARK: - Timings

    static let startDelay: TimeInterval = 0.60
    static let ghostLoopDuration: TimeInterval = 1.60
    static let ghostLoopCount = 3
    static let reduceMotionHold: TimeInterval = 3.50
    static let nudgeDuration: TimeInterval = 2.50

    // MARK: - State

    @Published private(set) var stage: Stage?
    /// When the walkthrough appeared, so a dismissal in the first moment can be
    /// told from a considered one.
    private var shownAt: TimeInterval = 0

    var policy: GestureCoachPolicy = .firstRun
    var defaults: UserDefaults = .standard
    var assistiveProbe: () -> AssistiveTechnologyState = { .current }
    weak var hud: GestureHUDModel?
    var onFinish: ((DismissReason) -> Void)?
    /// Resolves the symbol and copy for a side, so the coach never invents a
    /// mapping the router does not honour.
    var kindForSide: (RailSide) -> GestureKind? = { _ in nil }

    private let clock: GestureClock
    private var pendingTokens: [GestureCancellable] = []

    init(clock: GestureClock) {
        self.clock = clock
    }

    deinit {
        pendingTokens.forEach { $0.cancel() }
    }

    var isOnScreen: Bool { stage != nil }

    // MARK: - Trigger

    /// The only automatic trigger: the first frame of actual playback.
    ///
    /// Delayed a beat so the first thing the user sees is video, not a lesson.
    func playbackDidStart(capabilities: GestureCapabilities, geometry: GestureGeometry) {
        guard policy != .disabled else { return }
        cancelPending()
        schedule(after: Self.startDelay) { [weak self] in
            guard let self else { return }
            let sides = self.availableSides(capabilities: capabilities, geometry: geometry)
            guard Self.shouldPresent(
                policy: self.policy,
                completedVersion: self.defaults.integer(forKey: DefaultsKey.seenVersion),
                shownCount: self.defaults.integer(forKey: DefaultsKey.shownCount),
                assistive: self.assistiveProbe(),
                geometry: geometry,
                availableSides: sides
            ) else { return }
            self.present(sides: sides)
        }
    }

    /// Host and settings re-entry. Ignores every persistence gate.
    ///
    /// Re-entry is mandatory rather than optional: a one-time overlay that
    /// cannot be summoned again is a tutorial the user is not allowed to
    /// re-read.
    func present(capabilities: GestureCapabilities, geometry: GestureGeometry) {
        let sides = availableSides(capabilities: capabilities, geometry: geometry)
        guard !sides.isEmpty else { return }
        present(sides: sides)
    }

    private func present(sides: [RailSide]) {
        cancelPending()
        let reduceMotion = assistiveProbe().reduceMotion
        stage = .walkthrough(sides: sides, reduceMotion: reduceMotion)
        shownAt = clock.now

        // Written immediately rather than on dismissal: persisting on dismissal
        // means a crash re-shows the tutorial forever, and persisting only on a
        // *completed* run means the user's single most likely first action —
        // tapping to see the controls — resets it.
        defaults.set(defaults.integer(forKey: DefaultsKey.shownCount) + 1, forKey: DefaultsKey.shownCount)

        if reduceMotion {
            presentStaticRails(sides: sides)
            schedule(after: Self.reduceMotionHold) { [weak self] in self?.dismiss(.timeout) }
        } else {
            animateRails(sides: sides)
            let total = Self.ghostLoopDuration * Double(Self.ghostLoopCount)
            schedule(after: total) { [weak self] in self?.dismiss(.timeout) }
        }
    }

    // MARK: - Demo rails

    private func presentStaticRails(sides: [RailSide]) {
        for side in sides {
            hud?.setDemoRail(demoHUD(side: side, fraction: 0.55), for: side)
        }
    }

    /// Drives the **real** rail through its own model, at the same coordinates
    /// the live gesture uses.
    private func animateRails(sides: [RailSide]) {
        for side in sides {
            hud?.setDemoRail(demoHUD(side: side, fraction: 0.45), for: side)
        }
        for loop in 0 ..< Self.ghostLoopCount {
            let base = Double(loop) * Self.ghostLoopDuration
            schedule(after: base + Self.ghostLoopDuration * 0.33) { [weak self] in
                guard let self else { return }
                for side in sides { self.hud?.setDemoRail(self.demoHUD(side: side, fraction: 0.72), for: side) }
            }
            schedule(after: base + Self.ghostLoopDuration * 0.75) { [weak self] in
                guard let self else { return }
                for side in sides { self.hud?.setDemoRail(self.demoHUD(side: side, fraction: 0.45), for: side) }
            }
        }
    }

    private func demoHUD(side: RailSide, fraction: Double) -> GestureHUD {
        let kind = kindForSide(side) ?? .volume
        return GestureHUD(
            kind: kind == .brightness ? .brightness : .volume,
            slot: .rail(side),
            symbol: GestureManager.symbol(for: kind, unit: fraction),
            primary: "\(Int((fraction * 100).rounded()))%",
            secondary: nil,
            tertiary: nil,
            fraction: fraction,
            isDemo: true
        )
    }

    // MARK: - Copy

    /// Copy is chosen from the *capability set*, never from a platform string:
    /// where brightness is unavailable both halves drive volume, so it is one
    /// lesson, not two.
    func copy(for side: RailSide, sides: [RailSide], isAccessibilitySize: Bool) -> String {
        let kind = kindForSide(side) ?? .volume
        if isAccessibilitySize {
            return kind == .brightness ? "Brightness" : "Volume"
        }
        let bothSidesSameKind = sides.count == 2
            && kindForSide(.leading) == kindForSide(.trailing)
        if bothSidesSameKind {
            return kind == .brightness
                ? "Swipe up or down for brightness"
                : "Swipe up or down for volume"
        }
        return kind == .brightness ? "Swipe here for brightness" : "Swipe here for volume"
    }

    static func nudgeText(for kind: GestureKind) -> String {
        kind == .brightness
            ? "Swipe up and down here for brightness"
            : "Swipe up and down here for volume"
    }

    // MARK: - Dismissal

    /// Any touch dismisses, and the touch is **not** consumed — it reaches the
    /// router as normal.
    func noteTouch() {
        guard case .walkthrough = stage else { return }
        dismiss(.touched)
    }

    /// The user performed the very gesture being taught. The demo drops on the
    /// same frame and the rail becomes live under their finger.
    func noteGesturePerformed() {
        guard case .walkthrough = stage else { return }
        dismiss(.performed)
    }

    func dismiss(_ reason: DismissReason) {
        guard stage != nil else { return }
        let wasWalkthrough: Bool
        if case .walkthrough = stage { wasWalkthrough = true } else { wasWalkthrough = false }

        cancelPending()
        stage = nil
        hud?.clearDemoRails()

        if wasWalkthrough, Self.marksCompleted(reason, elapsed: clock.now - shownAt) {
            defaults.set(Self.currentVersion, forKey: DefaultsKey.seenVersion)
        }
        onFinish?(reason)
    }

    /// A tutorial that was *interrupted* is not a tutorial that was seen. A
    /// stray tap in the first moment leaves the flag alone so it gets one more
    /// chance, which is what the presentation cap is for.
    static func marksCompleted(_ reason: DismissReason, elapsed: TimeInterval) -> Bool {
        switch reason {
        case .timeout, .skipped, .performed:
            return true
        case .touched:
            return elapsed >= 1.5
        case .suppressed, .hostDisabled:
            return false
        }
    }

    // MARK: - Nudge

    /// Tier 3. A separate mechanism with no first-run flag: it fires for someone
    /// who has already tried and failed.
    func showNudge(side: RailSide, kind: GestureKind) {
        guard policy != .disabled else { return }
        guard stage == nil else { return }
        guard !assistiveProbe().suppressesCoach else { return }
        let count = defaults.integer(forKey: DefaultsKey.nudgeCount)
        guard count < Self.maximumNudges else { return }
        defaults.set(count + 1, forKey: DefaultsKey.nudgeCount)

        cancelPending()
        stage = .nudge(side: side, text: Self.nudgeText(for: kind))
        schedule(after: Self.nudgeDuration) { [weak self] in
            guard let self, case .nudge = self.stage else { return }
            self.cancelPending()
            self.stage = nil
        }
    }

    // MARK: - Gates

    func resetPersistedState() {
        defaults.removeObject(forKey: DefaultsKey.seenVersion)
        defaults.removeObject(forKey: DefaultsKey.shownCount)
        defaults.removeObject(forKey: DefaultsKey.nudgeCount)
    }

    private func availableSides(capabilities: GestureCapabilities, geometry: GestureGeometry) -> [RailSide] {
        RailSide.allCases.filter { side in
            guard let kind = geometry.kind(forSide: side) else { return false }
            return capabilities.availability(of: kind).isAvailable
        }
    }

    /// Pure and static, so the whole suppression matrix is table-testable.
    static func shouldPresent(
        policy: GestureCoachPolicy,
        completedVersion: Int,
        shownCount: Int,
        assistive: AssistiveTechnologyState,
        geometry: GestureGeometry,
        availableSides: [RailSide]
    ) -> Bool {
        // Checked first, so a host that turned it off pays nothing.
        guard policy != .disabled else { return false }
        // Does not consume a counter — it can still appear if the technology is
        // switched off later.
        guard !assistive.suppressesCoach else { return false }
        guard !availableSides.isEmpty else { return false }
        // A Mac pointer user has no swipe to be taught; their discoverability is
        // the keyboard shortcuts and the chrome.
        guard geometry.capabilities.usesTouch else { return false }
        // Never in a thumbnail embed.
        guard geometry.isUsable,
              geometry.activeRect.width >= 240,
              geometry.activeRect.height >= 160 else { return false }

        if policy == .always { return true }
        return completedVersion < currentVersion && shownCount < maximumPresentations
    }

    // MARK: - Scheduling

    private func schedule(after delay: TimeInterval, _ body: @escaping () -> Void) {
        pendingTokens.append(clock.schedule(after: delay, body))
    }

    private func cancelPending() {
        pendingTokens.forEach { $0.cancel() }
        pendingTokens.removeAll()
    }
}
