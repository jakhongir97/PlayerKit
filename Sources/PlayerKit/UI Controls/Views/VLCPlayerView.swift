#if canImport(VLCKit) || os(macOS)
#if canImport(VLCKit)
import VLCKit
#endif
#if canImport(UIKit)
import UIKit

public class VLCPlayerView: UIView {
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        self.backgroundColor = .black
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        for subview in subviews {
            subview.frame = bounds
        }
    }
}
#elseif canImport(AppKit)
import AppKit

public class VLCPlayerView: NSView {
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    public override func layout() {
        super.layout()

        for subview in subviews {
            subview.frame = bounds
        }
    }
}
#endif
#endif
