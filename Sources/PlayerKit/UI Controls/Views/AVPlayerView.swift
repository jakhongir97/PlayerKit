import AVKit

#if canImport(UIKit)
import UIKit

public class AVPlayerView: UIView {
    public override static var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
    
    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }
    
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }
}
#else
import AppKit

public class AVPlayerView: NSView {
    private let internalPlayerLayer = AVPlayerLayer()

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(internalPlayerLayer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.addSublayer(internalPlayerLayer)
    }

    public override func layout() {
        super.layout()
        internalPlayerLayer.frame = bounds
    }

    var playerLayer: AVPlayerLayer {
        internalPlayerLayer
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }
}
#endif
