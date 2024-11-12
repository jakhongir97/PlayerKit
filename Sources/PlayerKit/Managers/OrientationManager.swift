import SwiftUI
import UIKit
import Combine

public class OrientationManager: ObservableObject {
    public static let shared = OrientationManager()
    @Published var isLandscape: Bool = false

    private init() {}

    public func toggleOrientation() {
        isLandscape.toggle()
        updateOrientation()
    }

    private func updateOrientation() {
        let orientation: UIInterfaceOrientation = isLandscape ? .landscapeRight : .portrait
        UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        
        // Update supported orientations on the root view controller to apply the orientation
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            if #available(iOS 16.0, *) {
                rootViewController.setNeedsUpdateOfSupportedInterfaceOrientations()
            } else {
                // Fallback on earlier versions
            }
        }
    }
}
