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

extension View {
    @ViewBuilder
    func compatTint(_ color: Color) -> some View {
        if #available(iOS 15.0, *) {
            self.tint(color)
        } else {
            self.accentColor(color)
        }
    }
}


public extension View {
    /// Liquid Glass-style background across OS versions:
    /// - iOS 26+: real `glassEffect`
    /// - iOS 15–25: `.ultraThinMaterial`
    /// - iOS 13–14: translucent color fallback
    @ViewBuilder
    func glassBackgroundCompat(cornerRadius: CGFloat = 16) -> some View {
        if #available(iOS 26.0, *) {
            self
                .padding(12)
                .glassEffect(.clear, in: .rect(cornerRadius: cornerRadius, style: .continuous))
        } else if #available(iOS 15.0, *) {
            self
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1))
        } else {
            self
                .padding(12)
                .background(Color.black.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

public extension View {
    /// Uses `.monospacedDigit()` on iOS 15+, otherwise falls back to a monospaced font.
    @ViewBuilder
    func monospacedDigitsCompat() -> some View {
        if #available(iOS 15.0, *) {
            self.monospacedDigit()
        } else {
            // Approximation for iOS 13–14: switch to a monospaced design (all glyphs monospaced)
            self.font(.system(.caption, design: .monospaced))
        }
    }
}
