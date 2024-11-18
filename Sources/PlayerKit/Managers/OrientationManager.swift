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
        let orientationMask: UIInterfaceOrientationMask = isLandscape ? .landscapeRight : .portrait

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }

        if #available(iOS 16.0, *) {
            // Use UIWindowScene.requestGeometryUpdate(_:) in iOS 16 and later
            let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientationMask)
            windowScene.requestGeometryUpdate(geometryPreferences) { error in
                if error != nil {
                    print("Failed to request geometry update: \(error)")
                }
            }
        }
    }
}
