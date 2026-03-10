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
            .frame(width: 44, height: 44)
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
        return routePickerView
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
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
        return routePickerView
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
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
