import SwiftUI
import AVKit

@MainActor
struct AirPlayButton: View {
    @ObservedObject var playerManager: PlayerManager

    /// Sized off the shared bar metric like the rest of the top bar.
    ///
    /// AirPlay and Cast were the last controls still going through the legacy
    /// `circularGlassIcon` defaults, which resolve to a 50pt disc — so the top
    /// bar mixed 50pt route pickers with 44pt close/info/lock discs, the exact
    /// per-control size scatter this redesign exists to remove.
    private var extent: CGFloat { PlayerChromeMetrics.minimumHitTarget }

    var body: some View {
        #if canImport(AppKit)
        ZStack {
            Image(systemName: "airplayvideo")
                .playerControlIcon(appearance: playerManager.appearance)
                .allowsHitTesting(false)

            AirPlayRoutePickerView()
                .frame(width: extent, height: extent)
        }
        .frame(width: extent, height: extent)
        #else
        AirPlayRoutePickerView(
            accessibilityLabel: playerManager.strings.airPlay,
            accessibilityHint: playerManager.strings.airPlayHint
        )
            .playerControlIcon(appearance: playerManager.appearance)
        #endif
    }
}

#if canImport(UIKit)
struct AirPlayRoutePickerView: UIViewRepresentable {
    let accessibilityLabel: String
    let accessibilityHint: String

    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.activeTintColor = .blue
        routePickerView.tintColor = .white
        routePickerView.prioritizesVideoDevices = true
        configure(routePickerView)
        return routePickerView
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.activeTintColor = .blue
        uiView.tintColor = .white
        uiView.prioritizesVideoDevices = true
        configure(uiView)
    }

    private func configure(_ view: AVRoutePickerView) {
        view.accessibilityLabel = accessibilityLabel
        view.accessibilityHint = accessibilityHint
        view.accessibilityIdentifier = "player.airPlay"
    }
}
#elseif canImport(AppKit)
import AppKit

struct AirPlayRoutePickerView: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.isRoutePickerButtonBordered = false
        routePickerView.setRoutePickerButtonColor(.clear, for: .normal)
        routePickerView.setRoutePickerButtonColor(.clear, for: .normalHighlighted)
        routePickerView.setRoutePickerButtonColor(.clear, for: .active)
        routePickerView.setRoutePickerButtonColor(.clear, for: .activeHighlighted)
        routePickerView.setAccessibilityLabel("AirPlay")
        routePickerView.setAccessibilityHelp("Opens the AirPlay device picker")
        return routePickerView
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {
        nsView.setAccessibilityLabel("AirPlay")
        nsView.setAccessibilityHelp("Opens the AirPlay device picker")
    }
}
#else
struct AirPlayRoutePickerView: View {
    var body: some View {
        Image(systemName: "airplayaudio")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white)
    }
}
#endif
