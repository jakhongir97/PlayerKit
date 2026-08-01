import Combine
import CoreGraphics
import Foundation
import QuartzCore

/// The gesture layer's façade.
///
/// Everything with real behaviour now lives in `Sources/PlayerKit/Gestures/`:
/// `TapSeekMachine` owns the tap state machine, `VerticalRailController` drives
/// volume and brightness, `TouchClassifier` decides what a touch *is*, and the
/// effectors behind `OutputLevelControlling` do the platform work. This type
/// keeps the name, the callback surface and the two statics that the views and
/// the test suite already depend on, and translates between them.
public class GestureManager: ObservableObject {

    // MARK: - Published

    /// The double-tap seek overlay to draw, or `nil` when no session is running.
    ///
    /// A session starts on the second tap of a double tap and stays open for
    /// `seekSessionTimeout` after every tap, so the user can keep *single*
    /// tapping to skip further. The overlay is the single source of truth for
    /// the UI: side, accumulated seconds, and the point the ripple grows from.
    @Published private(set) var seekOverlay: DoubleTapSeekOverlayState?

    /// True while the user is skipping by tapping.
    ///
    /// The controls use this to keep the progress bar on screen while the
    /// playhead jumps, and `PlayerManager` uses it to stop an incoming
    /// interaction from re-showing the controls mid-session.
    var isDoubleTapSeeking: Bool { seekOverlay != nil }

    // MARK: - Callbacks

    var onSeek: ((_ newTime: Double) -> Void)?
    var onToggleControls: (() -> Void)?
    var onZoom: ((_ scale: CGFloat) -> Void)?
    var isLockedProvider: (() -> Bool)?
    var currentTimeProvider: (() -> Double)?
    var seekableRangeProvider: (() -> ClosedRange<Double>?)?
    var onControlsVisibilityChange: ((Bool) -> Void)?
    /// Whether the chrome is on screen. Feeds the deferred-toggle decision.
    var areControlsVisibleProvider: (() -> Bool)?
    /// Fires only when a seek session opens or closes — not on the taps in
    /// between.
    ///
    /// The controls need to know a session is running so they can hold the
    /// progress bar open, and nothing more. Letting them observe this manager
    /// instead re-ran the whole controls tree on every tap, because the tap id
    /// changes each time and `@ObservedObject` cannot subscribe per property.
    var onSeekSessionChange: ((Bool) -> Void)?
    /// Playback rate, for the speed-hold gesture.
    var speedProvider: (() -> Float)?
    var onSetSpeed: ((Float) -> Void)?
    var isPlayingProvider: (() -> Bool)?
    var onTogglePlayback: (() -> Void)?

    // MARK: - Zone contract

    /// Fraction of the width in the middle where a double tap does not seek.
    static let centerDeadZoneRatio: CGFloat = GestureGeometry.centerDeadZoneRatio

    /// How far in from either edge a seek tap can land, as a fraction of the
    /// width. The overlay sizes its tap ring against this so the ring never
    /// reaches across the midline.
    static var sideZoneWidthRatio: CGFloat { GestureGeometry.sideZoneWidthRatio }

    // MARK: - Composition

    let clock: GestureClock
    let machine: TapSeekMachine
    let rail = VerticalRailController()
    let scrub = ScrubController()
    let classifier = TouchClassifier()
    let speedHold = SpeedHoldController()
    let confusion = GestureConfusionDetector()
    let hudModel: GestureHUDModel
    let coach: GestureCoachModel

    /// Tier 1's arm timer and the speed-hold timer. Held so a lift, a cancel or
    /// a second finger can drop them before they fire.
    var armToken: GestureCancellable?
    var holdToken: GestureCancellable?
    /// Latched pinch direction, so hysteresis has something to compare against.
    var lastZoomFill: Bool?
    /// Scroll-wheel rail state (macOS).
    var scrollRailKind: GestureKind?
    var scrollRailSide: RailSide?
    var scrollIdleToken: GestureCancellable?
    var isZoomFilled = false

    private let assistiveObserver = AssistiveTechnologyObserver()
    var assistiveState: AssistiveTechnologyState { assistiveObserver.state }
    var feedbackPerformer: GestureFeedbackPerforming { HapticsManager.shared }

    let volumeControl = PlayerVolumeControl()
    let brightnessControl = ScreenBrightnessControl()

    #if os(iOS) && !targetEnvironment(macCatalyst)
    let systemVolumeControl = SystemVolumeControl()
    private let hudSuppressor = SystemVolumeHUDSuppressor()
    #endif

    var configuration = GestureConfiguration() {
        didSet { applyConfiguration() }
    }

    private(set) var geometry = GestureGeometry()

    /// Which rail, if any, the in-flight swipe is driving.
    var activeRailKind: GestureKind?
    var activeRailSide: RailSide?

    // MARK: - Init

    init(clock: GestureClock = RunLoopClock()) {
        self.clock = clock
        self.machine = TapSeekMachine(clock: clock)
        let hudModel = GestureHUDModel(clock: clock)
        self.hudModel = hudModel
        self.coach = GestureCoachModel(clock: clock)

        machine.emit = { [weak self] intent in self?.apply(intent) }
        machine.feedback = HapticsManager.shared
        machine.isLockedProvider = { [weak self] in self?.isLockedProvider?() ?? false }
        machine.currentTimeProvider = { [weak self] in self?.currentTimeProvider?() }
        machine.seekableRangeProvider = { [weak self] in self?.seekableRangeProvider?() ?? nil }
        machine.areControlsVisibleProvider = { [weak self] in
            guard let self, let provider = self.areControlsVisibleProvider else { return true }
            return provider()
        }

        brightnessControl.onDimScrim = { [weak self] value in
            self?.hudModel.setScrim(value)
        }
        volumeControl.systemVolumeProbe = {
            #if os(iOS)
            return PlayerVolumeControl.systemOutputVolume()
            #else
            return 1
            #endif
        }
        speedHold.speedProvider = { [weak self] in self?.speedProvider?() ?? 1 }
        speedHold.onSetSpeed = { [weak self] speed in self?.onSetSpeed?(speed) }
        speedHold.canEngage = { [weak self] in
            guard let self else { return false }
            return (self.isPlayingProvider?() ?? false) && !self.isLocked() && !self.isDoubleTapSeeking
        }

        coach.hud = hudModel
        coach.kindForSide = { [weak self] side in self?.geometry.kind(forSide: side) }
        coach.onFinish = { _ in
            NotificationCenter.default.post(name: .PlayerKitGestureCoachingDidFinish, object: nil)
        }

        applyConfiguration()
    }

    deinit {
        brightnessControl.relinquish(force: false)
    }

    private func applyConfiguration() {
        machine.skipInterval = configuration.skipInterval
        machine.isHapticsEnabled = configuration.isHapticsEnabled
        hudModel.dwell = configuration.hudDwell
        brightnessControl.mode = configuration.brightnessMode
        speedHold.multiplier = configuration.speedHoldMultiplier
        coach.policy = configuration.coachPolicy
        geometry.railMapping = configuration.railMapping
        geometry.capabilities = currentCapabilities()
    }

    // MARK: - Capabilities

    func currentCapabilities() -> GestureCapabilities {
        var capabilities = GestureCapabilities()
        capabilities.volume = configuration.isVolumeGestureEnabled
            ? activeVolumeControl.availability
            : .unavailable(.disabledByHost)
        capabilities.brightness = brightnessControl.availability
        capabilities.scrub = configuration.isScrubGestureEnabled
            ? (seekableRangeProvider?() != nil ? .available : .unavailable(.notSeekable))
            : .unavailable(.disabledByHost)
        capabilities.speedHold = configuration.isSpeedHoldEnabled ? .available : .unavailable(.disabledByHost)
        capabilities.zoom = configuration.isZoomGestureEnabled ? .available : .unavailable(.disabledByHost)
        #if os(macOS)
        capabilities.usesTouch = false
        #endif
        return capabilities
    }

    var activeVolumeControl: OutputLevelControlling {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if configuration.volumeTarget == .system { return systemVolumeControl }
        #endif
        return volumeControl
    }

    func control(for kind: GestureKind) -> OutputLevelControlling? {
        switch kind {
        case .volume: return activeVolumeControl
        case .brightness: return brightnessControl
        default: return nil
        }
    }

    // MARK: - Geometry

    func updateSurface(_ surface: SurfaceGeometry) {
        guard geometry.surface != surface else { return }
        geometry.surface = surface
    }

    /// A pure copy for a given surface, so a view body can ask "where are the
    /// rails" without mutating the manager mid-render. The authoritative update
    /// goes through `updateSurface(_:)` from the host's `updateUIView`.
    ///
    /// Capabilities are resolved **live** rather than read from the cached
    /// geometry. Caching them here was a real bug: they were first computed at
    /// `didMoveToWindow`, before the backend exists, so `volume` came back
    /// `.noBackend` and the volume half fell through to brightness. With
    /// autoplay off nothing ever recomputed them, so the volume gesture simply
    /// never arrived. Every input is a cheap closure read.
    func resolvedGeometry(for surface: SurfaceGeometry) -> GestureGeometry {
        GestureGeometry(
            surface: surface,
            capabilities: currentCapabilities(),
            railMapping: configuration.railMapping
        )
    }

    /// Tier 0 is shown only when there is already chrome for it to belong to.
    var showsRestingAffordance: Bool {
        configuration.showsRestingRailAffordance
            && (areControlsVisibleProvider?() ?? false)
            && !isLocked()
            && !isDoubleTapSeeking
    }

    func refreshCapabilities() {
        let next = currentCapabilities()
        guard geometry.capabilities != next else { return }
        geometry.capabilities = next
    }

    /// Called when the hosting window becomes known, which is what gives the
    /// brightness control a screen to write and mounts the volume HUD
    /// suppressor.
    func attachWindow(_ window: PKWindow?) {
        brightnessControl.window = window
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if window != nil {
            hudSuppressor.mount(in: window)
            if configuration.volumeTarget == .system {
                systemVolumeControl.mount(in: window)
            }
        } else {
            hudSuppressor.unmount()
            systemVolumeControl.unmount()
        }
        #endif
        refreshCapabilities()
    }

    // MARK: - Taps

    /// Routes one tap through the state machine.
    func handleTap(at location: CGPoint, in size: CGSize) {
        var geometry = self.geometry
        geometry.surface.size = size
        self.geometry = geometry
        machine.handleTap(
            unitOrigin: geometry.unitPoint(location),
            zone: geometry.tapZone(for: location)
        )
    }

    /// A skip with no fingertip behind it — buttons, rotor actions, keyboard.
    func skipForward() { machine.skip(.forward) }
    func skipBackward() { machine.skip(.backward) }

    /// Drops any in-flight tap session and its timers.
    ///
    /// `PlayerManager.tearDown()` and every media change call this, so a
    /// dismissed or re-loaded player does not leave a timer holding the manager
    /// alive with an overlay still published — or, worse, an anchor pointing at
    /// the previous item's playhead.
    func reset() {
        machine.reset()
        rail.cancel()
        scrub.cancel()
        activeRailKind = nil
        activeRailSide = nil
        hudModel.clearImmediately()
    }

    // MARK: - Rails

    func presentRail(
        kind: GestureKind,
        side: RailSide,
        unit: Double,
        isArmed: Bool,
        isPinned: Bool = false
    ) {
        hudModel.set(
            GestureHUD(
                kind: kind == .volume ? .volume : .brightness,
                slot: .rail(side),
                symbol: Self.symbol(for: kind, unit: unit),
                primary: "\(Int((unit * 100).rounded()))%",
                secondary: secondaryLine(for: kind),
                tertiary: nil,
                fraction: unit,
                isPinned: isPinned,
                isArmed: isArmed
            )
        )
    }

    private func secondaryLine(for kind: GestureKind) -> String? {
        guard kind == .volume, configuration.volumeTarget == .player else { return nil }
        return volumeControl.isLimitedByDeviceVolume ? "Device volume is low" : nil
    }

    static func symbol(for kind: GestureKind, unit: Double) -> String {
        switch kind {
        case .brightness:
            return unit < 0.34 ? "sun.min.fill" : (unit < 0.67 ? "sun.max" : "sun.max.fill")
        case .volume:
            if unit <= 0.001 { return "speaker.slash.fill" }
            if unit < 0.34 { return "speaker.wave.1.fill" }
            if unit < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        default:
            return "circle"
        }
    }

    // MARK: - Scrub presentation

    func presentScrub(_ sample: ScrubController.ScrubSample) {
        let signedDelta = sample.delta
        let sign = signedDelta < 0 ? "−" : "+"
        hudModel.set(
            GestureHUD(
                kind: .scrub,
                slot: .banner,
                symbol: signedDelta < 0 ? "backward.fill" : "forward.fill",
                primary: PlayerKitTimeFormatter.string(from: sample.target),
                secondary: sample.tier.label
                    ?? "\(sign)\(PlayerKitTimeFormatter.string(from: abs(signedDelta)))",
                tertiary: sample.tier.label == nil
                    ? nil
                    : "\(sign)\(PlayerKitTimeFormatter.string(from: abs(signedDelta)))",
                fraction: sample.unit
            )
        )
    }

    // MARK: - Confusion / coaching

    func emit(_ intent: GestureIntent) {
        apply(intent)
    }

    /// Repeated taps in one half by someone who has never swiped there is the
    /// "why isn't this doing anything" pattern — the best possible moment to
    /// answer the question.
    func noteTapForConfusion(at location: CGPoint) {
        guard configuration.showsConfusionNudges else { return }
        let side = geometry.railSide(for: location)
        guard let intent = confusion.noteTap(side: side, now: clock.now) else { return }
        apply(intent)
    }

    /// A rail that engaged and then lifted having barely moved is someone
    /// probing, not someone adjusting.
    func noteAbandonedAttempt(kind: GestureKind, side: RailSide) {
        guard configuration.showsConfusionNudges else { return }
        guard let intent = confusion.noteAdjustAttempt(
            kind: kind,
            side: side,
            travel: abs(classifier.lastTranslation.height - classifier.engagementTranslation.height)
        ) else { return }
        apply(intent)
    }

    func coachDidObserveRailEngagement() {
        confusion.noteRailEngaged()
        // The lesson completes by being done: the demo drops on this frame and
        // the rail goes live under the finger already on the glass.
        coach.noteGesturePerformed()
    }

    /// Called on the first frame of real playback.
    func playbackDidStart() {
        confusion.resetSession()
        refreshCapabilities()
        coach.playbackDidStart(capabilities: geometry.capabilities, geometry: geometry)
    }

    func showGestureCoach() {
        refreshCapabilities()
        coach.present(capabilities: geometry.capabilities, geometry: geometry)
    }

    // MARK: - Pinch

    func handlePinch(scale: CGFloat) {
        guard configuration.isZoomGestureEnabled, !isLocked() else { return }
        onZoom?(scale)
    }

    // MARK: - Teardown

    /// Restores the screen brightness PlayerKit found before it first adjusted
    /// it. Safe to call when the gesture was never used.
    func restoreSystemBrightness() {
        guard configuration.restoresBrightnessOnExit else { return }
        brightnessControl.relinquish(force: false)
        #if os(iOS) && !targetEnvironment(macCatalyst)
        hudSuppressor.unmount()
        systemVolumeControl.unmount()
        #endif
    }

    // MARK: - Intents

    private func apply(_ intent: GestureIntent) {
        switch intent {
        case .seek(let time):
            onSeek?(time)

        case .toggleControls(let policy):
            // A deferred toggle is a decision to do nothing *yet*; the machine
            // follows up with an immediate one if the double-tap window closes
            // without a second tap.
            guard policy == .immediate else { return }
            onToggleControls?()

        case .setControlsVisible(let isVisible):
            onControlsVisibilityChange?(isVisible)

        case .skipOverlay(let overlay):
            seekOverlay = overlay
            if let overlay {
                GestureAnnouncer.announce(
                    overlay.direction == .forward
                        ? "Forward \(Int(overlay.seconds.rounded())) seconds"
                        : "Back \(Int(overlay.seconds.rounded())) seconds",
                    state: assistiveState
                )
            }

        case .seekSession(let isOpen):
            onSeekSessionChange?(isOpen)

        case .blocked:
            if configuration.isHapticsEnabled {
                feedbackPerformer.notification(.warning)
            }
            hudModel.set(
                GestureHUD(
                    kind: .blocked,
                    slot: .center,
                    symbol: "lock.fill",
                    primary: "Locked",
                    secondary: nil,
                    tertiary: nil,
                    fraction: nil
                )
            )
            hudModel.beginDwell()

        case .togglePlayback:
            onTogglePlayback?()

        case .abandonedAdjustAttempt(let kind, let side):
            coach.showNudge(side: side, kind: kind)

        case .repeatedTapWithoutSwipe(let side):
            guard let kind = geometry.kind(forSide: side) else { return }
            coach.showNudge(side: side, kind: kind)

        case .zoom, .speedHoldBegan, .speedHoldEnded,
             .scrubBegan, .scrubChanged, .scrubEnded,
             .levelArmed, .levelBegan, .levelChanged, .levelPinned, .levelEnded,
             .axisLocked, .cancel:
            // Presentation for these is driven directly by the routing layer,
            // which already holds the sample. The intents exist so a test can
            // assert the sequence.
            break
        }
    }

    func isLocked() -> Bool {
        isLockedProvider?() ?? false
    }
}
