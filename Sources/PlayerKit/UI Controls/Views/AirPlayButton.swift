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

