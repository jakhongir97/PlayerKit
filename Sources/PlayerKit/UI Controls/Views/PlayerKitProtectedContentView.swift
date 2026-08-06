import Foundation

#if canImport(UIKit)
import UIKit

final class PlayerKitProtectedContentView: UIView {
    private let secureTextField = UITextField(frame: .zero)
    private let captureShieldView = UIView(frame: .zero)
    private let captureShieldLabel = UILabel(frame: .zero)
    private weak var protectedContentView: UIView?
    private var contentConstraints: [NSLayoutConstraint] = []
    private var policy: PlayerCaptureProtectionPolicy = .automatic
    private var screenIsCaptured = false

    var isContentHiddenForCapture: Bool {
        !captureShieldView.isHidden
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    deinit {
        NotificationCenter.default.removeObserver(
            self,
            name: UIScreen.capturedDidChangeNotification,
            object: nil
        )
    }

    func setProtectedContentView(_ contentView: UIView?) {
        guard protectedContentView !== contentView else {
            installProtectedContentIfPossible()
            return
        }

        NSLayoutConstraint.deactivate(contentConstraints)
        contentConstraints.removeAll()

        // Only detach a player view that is inside *our* subtree. SwiftUI builds
        // the replacement host before dismantling the one it replaces, so the
        // outgoing host would otherwise pull the video straight back out of the
        // incoming one. `layoutSubviews` re-installs and hides that here, but
        // the AppKit branch had no such recovery and went black.
        if let existing = protectedContentView, existing.isDescendant(of: self) {
            existing.removeFromSuperview()
        }

        protectedContentView = contentView
        installProtectedContentIfPossible()
    }

    func setCaptureMessage(_ message: String) {
        captureShieldLabel.text = message
        captureShieldView.accessibilityLabel = message
    }

    /// Switching to ``PlayerCaptureProtectionPolicy/allowCapture`` re-parents the
    /// player view out of the secure canvas, so the content has to move before
    /// the shield state is recomputed.
    func setCaptureProtectionPolicy(_ newPolicy: PlayerCaptureProtectionPolicy) {
        guard policy != newPolicy else { return }
        policy = newPolicy
        installProtectedContentIfPossible()
        applyCaptureState(screenIsCaptured)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        installProtectedContentIfPossible()
        bringSubviewToFront(captureShieldView)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateCaptureState()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let protectedContentView else {
            return super.hitTest(point, with: event)
        }

        let convertedPoint = convert(point, to: protectedContentView)
        return protectedContentView.hitTest(convertedPoint, with: event) ?? super.hitTest(point, with: event)
    }

    private func configure() {
        let captureMessage = PlayerStrings().videoHiddenDuringScreenSharing
        backgroundColor = .black
        clipsToBounds = true

        secureTextField.translatesAutoresizingMaskIntoConstraints = false
        secureTextField.backgroundColor = .black
        secureTextField.borderStyle = .none
        secureTextField.textColor = .clear
        secureTextField.tintColor = .clear
        secureTextField.autocorrectionType = .no
        secureTextField.spellCheckingType = .no
        secureTextField.isUserInteractionEnabled = false
        secureTextField.isSecureTextEntry = true

        addSubview(secureTextField)
        NSLayoutConstraint.activate([
            secureTextField.topAnchor.constraint(equalTo: topAnchor),
            secureTextField.bottomAnchor.constraint(equalTo: bottomAnchor),
            secureTextField.leadingAnchor.constraint(equalTo: leadingAnchor),
            secureTextField.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        captureShieldView.translatesAutoresizingMaskIntoConstraints = false
        captureShieldView.backgroundColor = .black
        captureShieldView.isUserInteractionEnabled = false
        captureShieldView.isAccessibilityElement = true
        captureShieldView.accessibilityLabel = captureMessage
        addSubview(captureShieldView)
        NSLayoutConstraint.activate([
            captureShieldView.topAnchor.constraint(equalTo: topAnchor),
            captureShieldView.bottomAnchor.constraint(equalTo: bottomAnchor),
            captureShieldView.leadingAnchor.constraint(equalTo: leadingAnchor),
            captureShieldView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        captureShieldLabel.translatesAutoresizingMaskIntoConstraints = false
        captureShieldLabel.text = captureMessage
        captureShieldLabel.textColor = .white
        captureShieldLabel.font = .preferredFont(forTextStyle: .headline)
        captureShieldLabel.adjustsFontForContentSizeCategory = true
        captureShieldLabel.numberOfLines = 0
        captureShieldLabel.textAlignment = .center
        captureShieldLabel.isAccessibilityElement = false
        captureShieldView.addSubview(captureShieldLabel)
        NSLayoutConstraint.activate([
            captureShieldLabel.centerXAnchor.constraint(equalTo: captureShieldView.centerXAnchor),
            captureShieldLabel.centerYAnchor.constraint(equalTo: captureShieldView.centerYAnchor),
            captureShieldLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: captureShieldView.leadingAnchor,
                constant: 24
            ),
            captureShieldLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: captureShieldView.trailingAnchor,
                constant: -24
            ),
        ])
        applyCaptureState(false)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(captureStateDidChange),
            name: UIScreen.capturedDidChangeNotification,
            object: nil
        )
    }

    @objc private func captureStateDidChange(_ notification: Notification) {
        guard let changedScreen = notification.object as? UIScreen else {
            updateCaptureState()
            return
        }

        let viewScreen = window?.windowScene?.screen
        guard viewScreen == nil || viewScreen === changedScreen else { return }
        updateCaptureState()
    }

    private func updateCaptureState() {
        guard let screen = window?.windowScene?.screen else {
            applyCaptureState(false)
            return
        }
        applyCaptureState(screen.isCaptured)
    }

    /// Active capture is a supported signal for recording, mirroring and remote
    /// control. It cannot retroactively hide a one-frame screenshot, so the
    /// secure-text canvas remains a best-effort additional layer.
    func applyCaptureState(_ isCaptured: Bool) {
        screenIsCaptured = isCaptured
        let isShielded = shouldShieldContent(screenIsCaptured: isCaptured)
        captureShieldView.isHidden = !isShielded
        captureShieldView.accessibilityElementsHidden = !isShielded
        protectedContentView?.accessibilityElementsHidden = isShielded
    }

    private func shouldShieldContent(screenIsCaptured: Bool) -> Bool {
        switch policy {
        case .automatic:
            return screenIsCaptured
        case .blackOutVideo:
            return true
        case .allowCapture:
            return false
        }
    }

    private func installProtectedContentIfPossible() {
        guard let protectedContentView else { return }

        let secureContainer = contentContainer

        if protectedContentView.superview !== secureContainer {
            protectedContentView.removeFromSuperview()
            secureContainer.addSubview(protectedContentView)
        }

        protectedContentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.deactivate(contentConstraints)
        contentConstraints = [
            protectedContentView.topAnchor.constraint(equalTo: secureContainer.topAnchor),
            protectedContentView.bottomAnchor.constraint(equalTo: secureContainer.bottomAnchor),
            protectedContentView.leadingAnchor.constraint(equalTo: secureContainer.leadingAnchor),
            protectedContentView.trailingAnchor.constraint(equalTo: secureContainer.trailingAnchor),
        ]
        NSLayoutConstraint.activate(contentConstraints)
        protectedContentView.accessibilityElementsHidden = isContentHiddenForCapture
        // `.allowCapture` parents the player view to `self`, which would
        // otherwise leave it in front of the shield.
        bringSubviewToFront(captureShieldView)
    }

    /// The secure canvas is what actually keeps the video out of a screenshot,
    /// so every protecting policy hosts the player view inside it.
    /// ``PlayerCaptureProtectionPolicy/allowCapture`` deliberately opts out and
    /// hosts the player view directly, which is what makes the video appear in
    /// captures.
    private var contentContainer: UIView {
        guard policy != .allowCapture else { return self }
        secureTextField.layoutIfNeeded()
        return secureCanvasView ?? secureTextField
    }

    private var secureCanvasView: UIView? {
        findSecureCanvas(in: secureTextField)
    }

    private func findSecureCanvas(in view: UIView) -> UIView? {
        for subview in view.subviews {
            if isSecureTextCanvas(subview) {
                return subview
            }

            if let match = findSecureCanvas(in: subview) {
                return match
            }
        }

        return nil
    }

    private func isSecureTextCanvas(_ view: UIView) -> Bool {
        let className = NSStringFromClass(type(of: view))
        return className.contains("TextLayoutCanvas")
            || className.contains("TextFieldCanvas")
            || className.contains("TextFieldContent")
    }
}

#elseif canImport(AppKit)
import AppKit

final class PlayerKitProtectedContentView: NSView {
    private weak var protectedContentView: NSView?
    private weak var protectedWindow: NSWindow?
    private var contentConstraints: [NSLayoutConstraint] = []
    private let captureShieldView = NSView(frame: .zero)
    private let captureShieldLabel = NSTextField(labelWithString: "")
    private var policy: PlayerCaptureProtectionPolicy = .automatic

    var isContentHiddenForCapture: Bool {
        !captureShieldView.isHidden
    }

    /// The capture shield is a permanent subview, so anything reasoning about
    /// *who owns the player view* has to discount it rather than counting raw
    /// `subviews`.
    var installedPlayerViews: [NSView] {
        subviews.filter { $0 !== captureShieldView }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func setProtectedContentView(_ contentView: NSView?) {
        guard protectedContentView !== contentView else {
            adoptProtectedContentIfOrphaned()
            return
        }

        NSLayoutConstraint.deactivate(contentConstraints)
        contentConstraints.removeAll()

        // Only ever detach the player view from *our own* hierarchy. SwiftUI
        // builds the replacement host before dismantling the one it replaces,
        // so by the time the outgoing host is torn down this same player view
        // is already a subview of the incoming one. Removing it from whatever
        // superview it currently has took the video straight back out of the
        // live host, leaving a `PlayerKitProtectedContentView` whose only
        // content is its own black backing layer.
        if protectedContentView?.superview === self {
            protectedContentView?.isHidden = false
            protectedContentView?.removeFromSuperview()
        }

        protectedContentView = contentView

        guard let contentView else { return }
        install(contentView)
    }

    func setCaptureMessage(_ message: String) {
        captureShieldLabel.stringValue = message
        captureShieldView.setAccessibilityLabel(message)
    }

    func setCaptureProtectionPolicy(_ newPolicy: PlayerCaptureProtectionPolicy) {
        guard policy != newPolicy else { return }
        policy = newPolicy
        applyPolicy()
    }

    override func layout() {
        super.layout()
        adoptProtectedContentIfOrphaned()
        raiseCaptureShield()
    }

    /// Passive recovery: re-adopt the player view only when nothing else owns
    /// it. Adopting unconditionally here would let a host that SwiftUI has not
    /// dismantled yet steal the video back out of the one that just took it.
    private func adoptProtectedContentIfOrphaned() {
        guard let contentView = protectedContentView, contentView.superview == nil else { return }
        install(contentView)
    }

    private func install(_ contentView: NSView) {
        guard contentView.superview !== self else { return }

        contentView.removeFromSuperview()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView, positioned: .below, relativeTo: captureShieldView)

        NSLayoutConstraint.deactivate(contentConstraints)
        contentConstraints = [
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ]
        NSLayoutConstraint.activate(contentConstraints)
        applyContentVisibility()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWindowProtection()
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        // AppKit has no secure-text canvas and no capture notification, so the
        // shield is not a reaction to a capture the way it is on iOS — it is the
        // whole mechanism behind `.blackOutVideo`, and it is opaque so the video
        // beneath it reaches neither the screen nor a capture.
        captureShieldView.translatesAutoresizingMaskIntoConstraints = false
        captureShieldView.wantsLayer = true
        captureShieldView.layer?.backgroundColor = NSColor.black.cgColor
        captureShieldView.isHidden = true
        captureShieldView.setAccessibilityElement(true)
        captureShieldView.setAccessibilityRole(.staticText)
        addSubview(captureShieldView)
        NSLayoutConstraint.activate([
            captureShieldView.topAnchor.constraint(equalTo: topAnchor),
            captureShieldView.bottomAnchor.constraint(equalTo: bottomAnchor),
            captureShieldView.leadingAnchor.constraint(equalTo: leadingAnchor),
            captureShieldView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        captureShieldLabel.translatesAutoresizingMaskIntoConstraints = false
        captureShieldLabel.textColor = .white
        captureShieldLabel.font = .preferredFont(forTextStyle: .headline)
        captureShieldLabel.alignment = .center
        captureShieldLabel.maximumNumberOfLines = 0
        captureShieldLabel.lineBreakMode = .byWordWrapping
        captureShieldLabel.setAccessibilityElement(false)
        captureShieldView.addSubview(captureShieldLabel)
        // Deliberately *not* centred. Unlike iOS — where the shield only appears
        // for the duration of an active capture — this one is a mode the viewer
        // sits in, and dead centre is exactly where the transport cluster lives,
        // which sliced the sentence into fragments between the buttons. A
        // proportional offset clears both the title chrome above and the
        // transport row at every window size.
        let verticalPlacement = NSLayoutConstraint(
            item: captureShieldLabel,
            attribute: .centerY,
            relatedBy: .equal,
            toItem: captureShieldView,
            attribute: .bottom,
            multiplier: 0.3,
            constant: 0
        )
        NSLayoutConstraint.activate([
            captureShieldLabel.centerXAnchor.constraint(equalTo: captureShieldView.centerXAnchor),
            verticalPlacement,
            captureShieldLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: captureShieldView.leadingAnchor,
                constant: 24
            ),
            captureShieldLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: captureShieldView.trailingAnchor,
                constant: -24
            ),
        ])

        setCaptureMessage(PlayerStrings().videoHiddenDuringScreenSharing)
    }

    private func applyPolicy() {
        updateWindowProtection()
        captureShieldView.isHidden = (policy != .blackOutVideo)
        applyContentVisibility()
        raiseCaptureShield()
    }

    /// The shield is opaque and covers the whole surface, so hiding the player
    /// view underneath is belt-and-braces rather than load-bearing. It also
    /// stops the compositor doing any work for pixels nobody can see, and it
    /// keeps `AVPlayer` running so audio and the transport timeline continue.
    private func applyContentVisibility() {
        protectedContentView?.isHidden = (policy == .blackOutVideo)
        protectedContentView?.setAccessibilityElement(policy != .blackOutVideo)
    }

    private func raiseCaptureShield() {
        guard captureShieldView.superview === self,
              subviews.last !== captureShieldView else { return }
        captureShieldView.removeFromSuperview()
        addSubview(captureShieldView, positioned: .above, relativeTo: nil)
    }

    /// Only ``PlayerCaptureProtectionPolicy/automatic`` takes the hosting window
    /// out of screen sharing. The other policies deliberately leave it
    /// capturable, and must therefore hand back any protection this view took
    /// out earlier — the policy can change while the player is on screen.
    private func updateWindowProtection() {
        let desiredWindow = (policy == .automatic) ? window : nil
        if protectedWindow === desiredWindow { return }

        releaseWindowProtection()

        guard let desiredWindow else { return }
        PlayerKitWindowCaptureProtectionRegistry.shared.retain(desiredWindow)
        protectedWindow = desiredWindow
    }

    private func releaseWindowProtection() {
        guard let protectedWindow else { return }
        PlayerKitWindowCaptureProtectionRegistry.shared.release(protectedWindow)
        self.protectedWindow = nil
    }
}

@MainActor
private final class PlayerKitWindowCaptureProtectionRegistry {
    static let shared = PlayerKitWindowCaptureProtectionRegistry()

    private struct State {
        weak var window: NSWindow?
        let originalSharingType: NSWindow.SharingType
        var retainCount: Int
    }

    private var states: [ObjectIdentifier: State] = [:]

    func retain(_ window: NSWindow) {
        pruneDeallocatedWindows()

        let identifier = ObjectIdentifier(window)
        // Only reuse an entry that still refers to *this* window. ObjectIdentifier
        // is derived from the address, so a deallocated window's identifier can
        // be handed to a new one — which would otherwise inherit a stale
        // originalSharingType and a non-zero retain count, permanently pinning
        // the new window to .none.
        if var state = states[identifier], state.window === window {
            state.retainCount += 1
            states[identifier] = state
        } else {
            states[identifier] = State(
                window: window,
                originalSharingType: window.sharingType,
                retainCount: 1
            )
        }

        window.sharingType = .none
    }

    /// Drops entries whose window has gone away, so their identifiers cannot be
    /// matched against a later window that happens to reuse the address.
    private func pruneDeallocatedWindows() {
        states = states.filter { $0.value.window != nil }
    }

    func release(_ window: NSWindow) {
        let identifier = ObjectIdentifier(window)
        guard var state = states[identifier] else { return }

        state.retainCount -= 1
        if state.retainCount <= 0 {
            if state.window === window {
                window.sharingType = state.originalSharingType
            }
            states.removeValue(forKey: identifier)
        } else {
            states[identifier] = state
        }
    }
}
#endif
