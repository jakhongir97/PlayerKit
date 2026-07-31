import Combine
import GameController

final class GameControllerManager: ObservableObject {
    static let shared = GameControllerManager()
    
    @Published var isAnyControllerConnected: Bool = false
    private var controllers: [GCController] = []
    let controllerEventPublisher = PassthroughSubject<GameControllerEvent, Never>()
    
    // MARK: - Scrubbing Properties
    private var scrubbingTimer: AnyCancellable?
    private let scrubInterval = 0.1
    private var currentScrubDirection: ScrubDirection = .forward
    private var currentScrubSpeed: Double = 0.0
    private let baseScrubRatePerSecond = 5.0
    
    private var leftBumperScrubEndWorkItem: DispatchWorkItem?
    private var rightBumperScrubEndWorkItem: DispatchWorkItem?
    private let delayInSeconds: Double = 1.0

    let ownership = SharedResourceOwnership()

    /// Whether PlayerKit's handlers are currently installed on the shared
    /// `GCController` instances. Tracked independently of ownership because
    /// `init` installs them before anyone has acquired.
    private(set) var areHandlersAttached = false

    /// How many times the controller handlers have actually been detached.
    private(set) var resourceReleaseCount = 0

    private init() {
        NotificationCenter.default.addObserver(self, selector: #selector(controllerDidConnect(_:)), name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(controllerDidDisconnect(_:)), name: .GCControllerDidDisconnect, object: nil)
        
        for controller in GCController.controllers() {
            configureController(controller)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func controllerDidConnect(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        configureController(controller)
        isAnyControllerConnected = !controllers.isEmpty
    }
    
    @objc private func controllerDidDisconnect(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        if let idx = controllers.firstIndex(of: controller) {
            controllers.remove(at: idx)
        }
        isAnyControllerConnected = !controllers.isEmpty
    }

    /// Detaches every handler PlayerKit installed, on behalf of `owner`.
    ///
    /// `GCController` instances are shared process-wide, so assigning these
    /// handlers overwrites whatever the host app had bound to the same buttons.
    /// Without this, dismissing the player left PlayerKit owning the host's
    /// controller input for the remaining lifetime of the process.
    ///
    /// Handlers stay attached until the last owner releases them: detaching
    /// unconditionally would take controller input away from a player that is
    /// still on screen as soon as any other player went away.
    func releaseControllerHandlers(for owner: AnyObject) {
        ownership.removeOwner(owner)
        // Detach whenever nobody holds the handlers, rather than only when the
        // caller happened to be the last registered owner. init() attaches
        // handlers to every already-connected controller without registering an
        // owner, so keying the detach on "was I the last owner" would leave
        // those attached forever on a teardown that never acquired.
        guard !ownership.isHeld else { return }
        guard areHandlersAttached else { return }
        areHandlersAttached = false
        resourceReleaseCount += 1

        for controller in controllers {
            guard let gamepad = controller.extendedGamepad else { continue }
            gamepad.buttonA.pressedChangedHandler = nil
            gamepad.buttonB.pressedChangedHandler = nil
            gamepad.leftShoulder.pressedChangedHandler = nil
            gamepad.rightShoulder.pressedChangedHandler = nil
            gamepad.leftTrigger.valueChangedHandler = nil
            gamepad.rightTrigger.valueChangedHandler = nil
            gamepad.dpad.left.pressedChangedHandler = nil
            gamepad.dpad.right.pressedChangedHandler = nil
        }
        stopScrubbing()
        leftBumperScrubEndWorkItem?.cancel()
        leftBumperScrubEndWorkItem = nil
        rightBumperScrubEndWorkItem?.cancel()
        rightBumperScrubEndWorkItem = nil
    }

    /// Re-attaches handlers for every currently connected controller, on behalf
    /// of `owner`.
    func attachControllerHandlers(for owner: AnyObject) {
        ownership.addOwner(owner)
        for controller in GCController.controllers() {
            configureController(controller)
        }
    }
    
    private func configureController(_ controller: GCController) {
        if !controllers.contains(controller) {
            controllers.append(controller)
        }
        
        isAnyControllerConnected = !controllers.isEmpty
        guard let gamepad = controller.extendedGamepad else { return }
        areHandlersAttached = true

        // A -> Play/Pause
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.controllerEventPublisher.send(.playPause) }
        }

        // B -> Close Player
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.controllerEventPublisher.send(.closePlayer) }
        }

        // LB -> Rewind 10s
        gamepad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            guard let self = self else { return }
            if pressed {
                self.leftBumperScrubEndWorkItem?.cancel()
                self.controllerEventPublisher.send(.scrubStarted)
                self.controllerEventPublisher.send(.rewind)
            } else {
                self.scheduleScrubEnded(for: &self.leftBumperScrubEndWorkItem)
            }
        }
        
        // RB -> Fast Forward 10s
        gamepad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            guard let self = self else { return }
            if pressed {
                self.rightBumperScrubEndWorkItem?.cancel()
                self.controllerEventPublisher.send(.scrubStarted)
                self.controllerEventPublisher.send(.fastForward)
            } else {
                self.scheduleScrubEnded(for: &self.rightBumperScrubEndWorkItem)
            }
        }

        // Left Trigger -> Rewind (Continuous)
        gamepad.leftTrigger.valueChangedHandler = { [weak self] _, value, pressed in
            guard let self = self else { return }
            if pressed {
                self.startScrubbing(direction: .backward, speed: Double(value))
            } else {
                self.stopScrubbing()
            }
        }

        // Right Trigger -> Fast Forward (Continuous)
        gamepad.rightTrigger.valueChangedHandler = { [weak self] _, value, pressed in
            guard let self = self else { return }
            if pressed {
                self.startScrubbing(direction: .forward, speed: Double(value))
            } else {
                self.stopScrubbing()
            }
        }

        // D-Pad Left -> Previous Video
        gamepad.dpad.left.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.controllerEventPublisher.send(.previousVideo) }
        }
        
        // D-Pad Right -> Next Video
        gamepad.dpad.right.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.controllerEventPublisher.send(.nextVideo) }
        }

        // D-Pad Up -> Focus Up
        gamepad.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.controllerEventPublisher.send(.focusUp) }
        }

        // D-Pad Down -> Focus Down
        gamepad.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.controllerEventPublisher.send(.focusDown) }
        }

        // X Button -> Select Focused Item
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.controllerEventPublisher.send(.focusSelect) }
        }
    }

    /// Helper to schedule `.scrubEnded` after a small delay.
    private func scheduleScrubEnded(for workItemRef: inout DispatchWorkItem?) {
        workItemRef?.cancel()
        let newWorkItem = DispatchWorkItem { [weak self] in
            self?.controllerEventPublisher.send(.scrubEnded)
        }
        workItemRef = newWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delayInSeconds, execute: newWorkItem)
    }

    // MARK: - Scrubbing Logic
    private func startScrubbing(direction: ScrubDirection, speed: Double) {
        scrubbingTimer?.cancel()
        
        currentScrubDirection = direction
        currentScrubSpeed = speed
        
        scrubbingTimer = Timer.publish(every: scrubInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                let scrubAmount = self.currentScrubSpeed * self.baseScrubRatePerSecond * self.scrubInterval
                
                switch self.currentScrubDirection {
                case .forward:
                    self.controllerEventPublisher.send(.fastForwardAmount(scrubAmount))
                case .backward:
                    self.controllerEventPublisher.send(.rewindAmount(scrubAmount))
                }
            }
        controllerEventPublisher.send(.scrubStarted)
    }
    
    private func stopScrubbing() {
        scrubbingTimer?.cancel()
        scrubbingTimer = nil
        controllerEventPublisher.send(.scrubEnded)
    }
}
