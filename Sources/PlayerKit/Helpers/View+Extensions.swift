import SwiftUI
import UIKit

extension View {
    /// Changes the device orientation to the specified orientation.
    func setDeviceOrientation(_ orientation: UIInterfaceOrientation) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }

        do {
            let orientationMask: UIInterfaceOrientationMask = (orientation == .landscapeLeft || orientation == .landscapeRight) ? .landscape : .portrait
            if #available(iOS 16.0, *) {
                try windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientationMask))
            } else {
                // Fallback on earlier versions
            }
            UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        } catch {
            print("Error setting orientation: \(error)")
        }
    }
    
    /// Changes the view's orientation to landscape.
    func landscape() -> some View {
        self.onAppear {
            setDeviceOrientation(.landscapeRight)
        }
    }
    
    /// Changes the view's orientation to portrait.
    func portrait() -> some View {
        self.onAppear {
            setDeviceOrientation(.portrait)
        }
    }
}

