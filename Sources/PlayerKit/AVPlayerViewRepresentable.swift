import SwiftUI
import AVFoundation
import UIKit

class PlayerUIView: UIView {
    private var playerLayer: AVPlayerLayer?

    var player: AVPlayer? {
        didSet {
            if let player = player {
                playerLayer?.removeFromSuperlayer()  // Remove existing playerLayer
                let newPlayerLayer = AVPlayerLayer(player: player)
                newPlayerLayer.videoGravity = .resizeAspect
                newPlayerLayer.frame = self.bounds
                self.layer.addSublayer(newPlayerLayer)
                self.playerLayer = newPlayerLayer
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Adjust playerLayer to match the view's bounds when the view is resized
        playerLayer?.frame = self.bounds
    }
}

struct AVPlayerViewRepresentable: UIViewRepresentable {
    var player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.player = player
    }
}

