import SwiftUI
import AVKit
import GoogleCast

struct CastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        
        let largeConfig = UIImage.SymbolConfiguration(pointSize: 30, weight: .bold, scale: .small)
        let largeImage = UIImage(systemName: "airplayvideo", withConfiguration: largeConfig)
        button.setImage(largeImage, for: .normal)
        
        button.tintColor = .white
        setupCastButton(for: button)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        // No need to update for now
    }

    // Setup the cast button with both AirPlay and Chromecast actions
    private func setupCastButton(for button: UIButton) {
        // Create AVRoutePickerView for AirPlay
        let airplayButton = AVRoutePickerView()
        
        // AirPlay action that programmatically triggers the AirPlay button
        let airPlayAction = UIAction(title: "AirPlay", image: UIImage(systemName: "airplayaudio")) { _ in
            for view in airplayButton.subviews {
                if let button = view as? UIButton {
                    button.sendActions(for: .touchUpInside)
                    break
                }
            }
        }

        // Google Cast action that triggers the Chromecast dialog
        let googleCastAction = UIAction(title: "Chromecast", image: UIImage.fromFramework(named: "chromecast")) { _ in
            if GCKCastContext.sharedInstance().castState != .noDevicesAvailable {
                GCKCastContext.sharedInstance().presentCastDialog()
            } else {
                print("No Chromecast devices available")
            }
        }

        // Combine both actions into a UIMenu
        let castMenu = UIMenu(title: "Cast Options", children: [googleCastAction, airPlayAction])

        // Set the menu on the button
        if #available(iOS 14.0, *) {
            button.menu = castMenu
            button.showsMenuAsPrimaryAction = true
        }
    }
}

