import SwiftUI
import AVKit
#if canImport(UIKit) && canImport(GoogleCast)
import GoogleCast

struct CastButton: UIViewRepresentable {
    /// Chromecast handoff is independent of `AVPlayer.allowsExternalPlayback`,
    /// so only the AirPlay entry is gated on it.
    var isAirPlayEnabled: Bool = false

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)

        let largeConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium, scale: .small)
        let largeImage = UIImage(systemName: "airplayvideo", withConfiguration: largeConfig)
        button.setImage(largeImage, for: .normal)

        button.tintColor = .white
        button.accessibilityLabel = "Cast options"
        button.accessibilityHint = isAirPlayEnabled
            ? "Shows AirPlay and Chromecast options"
            : "Shows Chromecast options"
        button.accessibilityIdentifier = "player.cast"
        setupCastButton(for: button)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        setupCastButton(for: uiView)
    }

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
                PlayerKitLog.debug("CastButton", "No Chromecast devices available")
            }
        }

        let actions = isAirPlayEnabled ? [googleCastAction, airPlayAction] : [googleCastAction]
        let castMenu = UIMenu(title: "Cast Options", children: actions)
        button.menu = castMenu
        button.showsMenuAsPrimaryAction = true
    }
}
#elseif os(macOS)
struct CastButton: View {
    var isAirPlayEnabled: Bool = false

    var body: some View {
        // On macOS this button *is* the AirPlay picker, so with external
        // playback disabled there is nothing to show.
        if isAirPlayEnabled {
            AirPlayButton()
                .accessibilityLabel("AirPlay")
                .accessibilityHint("Opens the AirPlay device picker")
                .accessibilityIdentifier("player.cast")
        }
    }
}
#else
struct CastButton: View {
    var isAirPlayEnabled: Bool = false

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
