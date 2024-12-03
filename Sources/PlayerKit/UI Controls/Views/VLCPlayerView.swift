import UIKit
import VLCKit

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
