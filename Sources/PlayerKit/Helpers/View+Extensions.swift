import SwiftUI
import UIKit

extension View {
    /// Sets the device orientation to the specified `UIInterfaceOrientation`.
    func setDeviceOrientation(_ orientation: UIInterfaceOrientation) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }

        DispatchQueue.main.async {
            let orientationMask = orientation.toInterfaceOrientationMask()

            if #available(iOS 16.0, *) {
                let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientationMask)
                do {
                    try windowScene.requestGeometryUpdate(geometryPreferences)
                } catch {
                    print("Failed to set orientation: \(error)")
                }
            } else {
                UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
                UINavigationController.attemptRotationToDeviceOrientation()
            }
        }
    }

    /// Sets the view's orientation to landscape on appearance.
    func landscape() -> some View {
        self.onAppear {
            setDeviceOrientation(.landscapeRight)
        }
    }

    /// Sets the view's orientation to portrait on appearance.
    func portrait() -> some View {
        self.onAppear {
            setDeviceOrientation(.portrait)
        }
    }
}

extension UIInterfaceOrientation {
    /// Converts `UIInterfaceOrientation` to its corresponding `UIInterfaceOrientationMask`.
    func toInterfaceOrientationMask() -> UIInterfaceOrientationMask {
        switch self {
        case .portrait:
            return .portrait
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        case .portraitUpsideDown:
            return .portraitUpsideDown
        @unknown default:
            return .portrait
        }
    }
}

extension View {
    /// Applies hierarchical rendering mode to an SF Symbol image if available.
    @ViewBuilder
    func hierarchicalSymbolRendering() -> some View {
        if #available(iOS 15.0, *) {
            self.symbolRenderingMode(.hierarchical)
        } else {
            self // For earlier versions, return the view unmodified
        }
    }
}

extension View {
    @ViewBuilder
    func glassStyleIfAvailable() -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.clear)
                .buttonStyle(.glass)
        } else {
            self
        }
    }
}
