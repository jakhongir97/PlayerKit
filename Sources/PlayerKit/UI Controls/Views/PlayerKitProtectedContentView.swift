import Foundation

#if canImport(UIKit)
import UIKit

final class PlayerKitProtectedContentView: UIView {
    private let secureTextField = UITextField(frame: .zero)
    private let captureShieldView = UIView(frame: .zero)
    private let captureShieldLabel = UILabel(frame: .zero)
    private weak var protectedContentView: UIView?
    private var contentConstraints: [NSLayoutConstraint] = []

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
        captureShieldView.isHidden = !isCaptured
        captureShieldView.accessibilityElementsHidden = !isCaptured
        protectedContentView?.accessibilityElementsHidden = isCaptured
    }

    private func installProtectedContentIfPossible() {
        guard let protectedContentView else { return }

        secureTextField.layoutIfNeeded()
        let secureContainer = secureCanvasView ?? secureTextField

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
            protectedContentView?.removeFromSuperview()
        }

        protectedContentView = contentView

        guard let contentView else { return }
        install(contentView)
    }

    override func layout() {
        super.layout()
        adoptProtectedContentIfOrphaned()
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
        addSubview(contentView)

        NSLayoutConstraint.deactivate(contentConstraints)
        contentConstraints = [
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ]
        NSLayoutConstraint.activate(contentConstraints)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWindowProtection()
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    private func updateWindowProtection() {
        if protectedWindow === window { return }

        releaseWindowProtection()

        guard let window else { return }
        PlayerKitWindowCaptureProtectionRegistry.shared.retain(window)
        protectedWindow = window
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
