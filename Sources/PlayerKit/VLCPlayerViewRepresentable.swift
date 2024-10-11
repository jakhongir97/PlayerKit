import SwiftUI
import VLCKit

struct VLCPlayerViewRepresentable: UIViewRepresentable {
    var player: VLCMediaPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()

        // Set the drawable after the view is fully initialized
        DispatchQueue.main.async {
            if player.drawable == nil {
                print("Setting drawable in makeUIView.")
                self.player.drawable = view
            }
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Ensure the drawable is set during updates
        DispatchQueue.main.async {
            if player.drawable == nil {
                print("Updating drawable in updateUIView.")
                self.player.drawable = uiView
            }
        }
    }

    // Handle view removal or player cleanup
    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        DispatchQueue.main.async {
            if let player = uiView.layer.sublayers?.first as? VLCMediaPlayer {
                player.stop()
            }
        }
    }
}

