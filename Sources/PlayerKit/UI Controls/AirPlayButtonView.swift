import SwiftUI
import AVKit

struct AirPlayRoutePickerView: UIViewRepresentable {

    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.activeTintColor = .blue  // Customize active color
        routePickerView.tintColor = .white       // Customize default tint color

        return routePickerView
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        // No need to update the view in this case
    }
}


