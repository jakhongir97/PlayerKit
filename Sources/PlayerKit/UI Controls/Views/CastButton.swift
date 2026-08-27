import SwiftUI

#if canImport(UIKit) && canImport(GoogleCast)
import GoogleCast
import UIKit

/// Google's official Cast control. The SDK context exists before the control
/// is created, while receiver discovery remains deferred until user intent.
@MainActor
struct CastButton: UIViewRepresentable {
    let playerManager: PlayerManager

    func makeUIView(context: Context) -> GCKUICastButton {
        _ = playerManager.prepareChromecastButton()
        let button = GCKUICastButton(frame: .zero)
        configure(button)
        return button
    }

    func updateUIView(_ uiView: GCKUICastButton, context: Context) {
        configure(uiView)
    }

    private func configure(_ button: GCKUICastButton) {
        button.tintColor = .white
        button.accessibilityLabel = playerManager.strings.chromecast
        button.accessibilityHint = playerManager.strings.chromecastHint
        button.accessibilityIdentifier = "player.cast"
    }
}
#endif
