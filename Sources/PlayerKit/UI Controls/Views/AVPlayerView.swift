import SwiftUI
import AVFoundation
import UIKit

class AVPlayerView: UIView {
    public var playerLayer: AVPlayerLayer?

    var player: AVPlayer? {
        didSet {
            playerLayer?.removeFromSuperlayer()  // Remove any existing playerLayer to prevent overlaps
            guard let player = player else { return }
            let newPlayerLayer = AVPlayerLayer(player: player)
            newPlayerLayer.videoGravity = .resizeAspect
            newPlayerLayer.frame = bounds
            layer.addSublayer(newPlayerLayer)
            playerLayer = newPlayerLayer
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
}

