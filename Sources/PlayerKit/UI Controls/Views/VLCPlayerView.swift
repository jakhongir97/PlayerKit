import UIKit
import VLCKit

public class VLCPlayerView: UIView {
    public var player: VLCMediaPlayer? {
        didSet {
            player?.drawable = self
        }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        self.backgroundColor = .red
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        player?.drawable = self
    }
}
