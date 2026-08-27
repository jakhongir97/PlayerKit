import SwiftUI
import AVKit

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
        configure(routePickerView)
        return routePickerView
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: AVRoutePickerView) {
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("AirPlay")
        view.setAccessibilityHelp("Opens the AirPlay device picker")
        view.setAccessibilityIdentifier("player.airPlay")
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
