import SwiftUI
import AVKit
#if canImport(UIKit) && canImport(GoogleCast)
import GoogleCast

struct CastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)

        let largeConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium, scale: .small)
        let largeImage = UIImage(systemName: "airplayvideo", withConfiguration: largeConfig)
        button.setImage(largeImage, for: .normal)

        button.tintColor = .white
        button.accessibilityLabel = "Cast options"
        button.accessibilityHint = "Shows AirPlay and Chromecast options"
        button.accessibilityIdentifier = "player.cast"
        setupCastButton(for: button)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}

    private func setupCastButton(for button: UIButton) {
        let airplayButton = AVRoutePickerView()

        let airPlayAction = UIAction(title: "AirPlay", image: UIImage(systemName: "airplayaudio")) { _ in
            for view in airplayButton.subviews {
                if let button = view as? UIButton {
                    button.sendActions(for: .touchUpInside)
                    break
                }
            }
        }

        let googleCastAction = UIAction(title: "Chromecast", image: UIImage.fromFramework(named: "chromecast")) { _ in
            if GCKCastContext.sharedInstance().castState != .noDevicesAvailable {
                GCKCastContext.sharedInstance().presentCastDialog()
            } else {
                print("No Chromecast devices available")
            }
        }

        let castMenu = UIMenu(title: "Cast Options", children: [googleCastAction, airPlayAction])
        if #available(iOS 14.0, *) {
            button.menu = castMenu
            button.showsMenuAsPrimaryAction = true
        }
    }
}
#else
struct CastButton: View {
    var body: some View {
        Image(systemName: "airplayvideo")
            .font(.system(size: 20, weight: .semibold))
            .foregroundColor(.white)
            .padding(10)
            .accessibilityLabel("Cast unavailable")
            .accessibilityHint("Casting is currently available on iOS builds.")
            .accessibilityIdentifier("player.cast")
    }
}
#endif
