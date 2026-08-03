import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum PinchPhase: Equatable {
    case began
    case changed
    case ended
    case cancelled
}

enum ScrollPhase: Equatable {
    case began
    case changed
    case ended
}

#if canImport(UIKit)

/// The only platform bridge in the gesture layer.
///
/// A `UIView` rather than a SwiftUI `DragGesture`, for one decisive reason:
/// `touchesCancelled` is the signal UIKit *guarantees* when a system recogniser
/// claims the sequence — a screen-edge swipe, Notification Centre, the Slide
/// Over divider, an incoming call banner. SwiftUI's drag gesture simply stops
/// calling you, which is indistinguishable from a finger that stopped moving,
/// and is why a stolen touch used to leave a half-applied volume change behind.
///
/// It also hands us `event.allTouches?.count` for free, so a second finger is
/// known at the moment it lands rather than inferred, and a real `touchesBegan`,
/// which removes the "is this a fresh touch?" guesswork entirely.
final class PlayerKitTouchHostView: UIView {

    weak var manager: GestureManager?
    var onWindowChange: ((UIWindow?) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isUserInteractionEnabled = true
        backgroundColor = .clear

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)

        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.delegate = self
        addGestureRecognizer(twoFingerTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window)
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        manager?.touchesBegan(
            at: touch.location(in: self),
            touchCount: event?.allTouches?.count ?? touches.count,
            source: source(for: touch)
        )
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first else { return }
        manager?.touchesMoved(
            to: touch.location(in: self),
            touchCount: event?.allTouches?.count ?? touches.count
        )
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard let touch = touches.first else { return }
        manager?.touchesEnded(
            at: touch.location(in: self),
            touchCount: event?.allTouches?.count ?? touches.count
        )
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        manager?.touchesCancelled()
    }

    private func source(for touch: UITouch) -> PointerSource {
        if #available(iOS 13.4, *), touch.type == .indirectPointer { return .pointer }
        return .touch
    }

    // MARK: - Recognisers

    @objc private func handlePinch(_ recogniser: UIPinchGestureRecognizer) {
        switch recogniser.state {
        case .began: manager?.pinchChanged(scale: recogniser.scale, phase: .began)
        case .changed: manager?.pinchChanged(scale: recogniser.scale, phase: .changed)
        case .ended: manager?.pinchChanged(scale: recogniser.scale, phase: .ended)
        case .cancelled, .failed: manager?.pinchChanged(scale: recogniser.scale, phase: .cancelled)
        default: break
        }
    }

    @objc private func handleTwoFingerTap(_ recogniser: UITapGestureRecognizer) {
        guard recogniser.state == .ended else { return }
        manager?.twoFingerTap()
    }

    /// Sends a synthetic cancel *before* any recogniser on this view begins, so
    /// a pinch or a two-finger tap can never also be delivered as a tap or ride
    /// a rail.
    ///
    /// `UIView` declares this itself — it is not only a `UIGestureRecognizerDelegate`
    /// method — so it has to be an override, and therefore has to live in the
    /// class body rather than in the delegate extension.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        manager?.abandonTouch()
        return true
    }
}

extension PlayerKitTouchHostView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

struct GestureTouchHost: UIViewRepresentable {
    let manager: GestureManager
    let surface: SurfaceGeometry
    let onWindow: (PKWindow?) -> Void

    func makeUIView(context: Context) -> PlayerKitTouchHostView {
        let view = PlayerKitTouchHostView(frame: .zero)
        view.manager = manager
        view.onWindowChange = onWindow
        return view
    }

    /// Pushes geometry down and nothing else. It never rebuilds a recogniser and
    /// never allocates, so a resize does not disturb a touch in flight.
    func updateUIView(_ uiView: PlayerKitTouchHostView, context: Context) {
        uiView.manager = manager
        manager.updateSurface(surface)
    }
}

#elseif canImport(AppKit)

/// The desktop bridge.
///
/// macOS gets genuinely working input rather than the `#else` stub the old
/// gesture code compiled: scroll wheel drives the rails, `magnify(with:)` drives
/// fit/fill, and the keyboard is the real discoverability story on a machine
/// with no touchscreen to swipe.
final class PlayerKitPointerHostView: NSView {

    weak var manager: GestureManager?
    var onWindowChange: ((NSWindow?) -> Void)?

    private var scrollAccumulator: CGSize = .zero
    private var isScrolling = false
    private var magnificationScale: CGFloat = 1

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }

    private func location(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        // AppKit's origin is bottom-left; every geometry calculation in this
        // layer is top-left, like the touch platforms.
        return CGPoint(x: point.x, y: bounds.height - point.y)
    }

    override func mouseDown(with event: NSEvent) {
        // Mounting a player must not steal focus from a text field or another
        // control. An intentional click on the video is the point at which its
        // keyboard shortcuts become active.
        window?.makeFirstResponder(self)
        manager?.touchesBegan(at: location(event), touchCount: 1, source: .pointer)
    }

    override func mouseDragged(with event: NSEvent) {
        manager?.touchesMoved(to: location(event), touchCount: 1)
    }

    override func mouseUp(with event: NSEvent) {
        manager?.touchesEnded(at: location(event), touchCount: 1)
    }

    override func mouseExited(with event: NSEvent) {
        manager?.touchesCancelled()
    }

    override func magnify(with event: NSEvent) {
        switch event.phase {
        case .began:
            magnificationScale = 1
            manager?.pinchChanged(scale: magnificationScale, phase: .began)
            magnificationScale = max(magnificationScale + event.magnification, 0.01)
            manager?.pinchChanged(scale: magnificationScale, phase: .changed)
        case .ended:
            magnificationScale = max(magnificationScale + event.magnification, 0.01)
            manager?.pinchChanged(scale: magnificationScale, phase: .changed)
            manager?.pinchChanged(scale: magnificationScale, phase: .ended)
            magnificationScale = 1
        case .cancelled:
            manager?.pinchChanged(scale: magnificationScale, phase: .cancelled)
            magnificationScale = 1
        default:
            // NSEvent reports an incremental magnification delta, unlike
            // UIPinchGestureRecognizer.scale. Accumulate it across the gesture
            // before applying the shared fit/fill thresholds.
            magnificationScale = max(magnificationScale + event.magnification, 0.01)
            manager?.pinchChanged(scale: magnificationScale, phase: .changed)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let phase: ScrollPhase
        if event.phase == .began || !isScrolling {
            phase = .began
            isScrolling = true
        } else if event.phase == .ended || event.momentumPhase == .ended {
            phase = .ended
            isScrolling = false
        } else {
            phase = .changed
        }
        manager?.scrollWheel(
            at: location(event),
            delta: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY),
            phase: phase
        )
    }

    override func keyDown(with event: NSEvent) {
        guard !Self.hasReservedShortcutModifier(event.modifierFlags) else {
            return super.keyDown(with: event)
        }
        guard let manager else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 49: manager.twoFingerTap()                        // space
        case 123: manager.skipBackward()                       // ←
        case 124: manager.skipForward()                        // →
        case 126: manager.nudge(.volume, .increment)           // ↑
        case 125: manager.nudge(.volume, .decrement)           // ↓
        case 3: manager.toggleZoom()                           // F
        default: super.keyDown(with: event)
        }
    }

    static func hasReservedShortcutModifier(_ flags: NSEvent.ModifierFlags) -> Bool {
        !flags.intersection([.command, .control, .option]).isEmpty
    }
}

struct GestureTouchHost: NSViewRepresentable {
    let manager: GestureManager
    let surface: SurfaceGeometry
    let onWindow: (PKWindow?) -> Void

    func makeNSView(context: Context) -> PlayerKitPointerHostView {
        let view = PlayerKitPointerHostView(frame: .zero)
        view.manager = manager
        view.onWindowChange = onWindow
        return view
    }

    func updateNSView(_ nsView: PlayerKitPointerHostView, context: Context) {
        nsView.manager = manager
        manager.updateSurface(surface)
    }
}

#endif
