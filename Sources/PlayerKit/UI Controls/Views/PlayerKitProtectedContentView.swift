import Foundation

#if canImport(UIKit)
import UIKit

final class PlayerKitProtectedContentView: UIView {
    private let secureTextField = UITextField(frame: .zero)
    private weak var protectedContentView: UIView?
    private var contentConstraints: [NSLayoutConstraint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func setProtectedContentView(_ contentView: UIView?) {
        guard protectedContentView !== contentView else {
            installProtectedContentIfPossible()
            return
        }

        NSLayoutConstraint.deactivate(contentConstraints)
        contentConstraints.removeAll()

        if protectedContentView?.superview != nil {
            protectedContentView?.removeFromSuperview()
        }

        protectedContentView = contentView
        installProtectedContentIfPossible()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        installProtectedContentIfPossible()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let protectedContentView else {
            return super.hitTest(point, with: event)
        }

        let convertedPoint = convert(point, to: protectedContentView)
        return protectedContentView.hitTest(convertedPoint, with: event) ?? super.hitTest(point, with: event)
    }

    private func configure() {
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

    deinit {
        releaseWindowProtection()
    }

    func setProtectedContentView(_ contentView: NSView?) {
        guard protectedContentView !== contentView else { return }

        NSLayoutConstraint.deactivate(contentConstraints)
        contentConstraints.removeAll()

        if protectedContentView?.superview != nil {
            protectedContentView?.removeFromSuperview()
        }

        protectedContentView = contentView

        guard let contentView else { return }
        contentView.removeFromSuperview()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
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

private final class PlayerKitWindowCaptureProtectionRegistry {
    static let shared = PlayerKitWindowCaptureProtectionRegistry()

    private struct State {
        weak var window: NSWindow?
        let originalSharingType: NSWindow.SharingType
        var retainCount: Int
    }

    private var states: [ObjectIdentifier: State] = [:]

    func retain(_ window: NSWindow) {
        let identifier = ObjectIdentifier(window)
        if var state = states[identifier] {
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
