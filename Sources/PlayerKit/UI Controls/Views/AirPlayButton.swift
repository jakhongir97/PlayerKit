import SwiftUI
import AVKit

struct AirPlayButton: View {
    var body: some View {
        HStack {
            AirPlayRoutePickerView()
                .frame(width: 44, height: 44)  // Adjust size as needed
        }
    }
}

#if canImport(UIKit)
struct AirPlayRoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.activeTintColor = .blue
        routePickerView.tintColor = .white
        return routePickerView
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
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
