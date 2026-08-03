import SwiftUI
import AVKit

struct AirPlayButton: View {
    var body: some View {
        #if canImport(AppKit)
        ZStack {
            Image(systemName: "airplayvideo")
                .circularGlassIcon()
                .allowsHitTesting(false)

            AirPlayRoutePickerView()
                .frame(width: 50, height: 50)
        }
        .frame(width: 50, height: 50)
        #else
        AirPlayRoutePickerView()
            .circularGlassIcon()
        #endif
    }
}

#if canImport(UIKit)
struct AirPlayRoutePickerView: UIViewRepresentable {
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
        view.accessibilityLabel = "AirPlay"
        view.accessibilityHint = "Opens the AirPlay device picker"
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
