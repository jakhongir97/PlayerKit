import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
extension View {
    func setDeviceOrientation(_ orientation: UIInterfaceOrientation) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }

        DispatchQueue.main.async {
            let orientationMask = orientation.toInterfaceOrientationMask()

            if #available(iOS 16.0, *) {
                let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientationMask)
                windowScene.requestGeometryUpdate(geometryPreferences) { error in
                    PlayerKitLog.debug("Orientation", "Failed to set orientation: \(error)")
                }
            } else {
                UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
                UINavigationController.attemptRotationToDeviceOrientation()
            }
        }
    }

    func landscape() -> some View {
        self.onAppear {
            setDeviceOrientation(.landscapeRight)
        }
    }

    func portrait() -> some View {
        self.onAppear {
            setDeviceOrientation(.portrait)
        }
    }
}

extension UIInterfaceOrientation {
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
        case .unknown:
            return .portrait
        @unknown default:
            return .portrait
        }
    }
}
#else
extension View {
    func landscape() -> some View { self }
    func portrait() -> some View { self }
}
#endif

extension View {
    @ViewBuilder
    func glassStyleIfAvailable() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .glassEffect(.clear)
                .buttonStyle(.glass)
        } else {
            self
        }
    }
}

public extension View {
    @ViewBuilder
    func glassBackgroundCompat(cornerRadius: CGFloat = 16) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .padding(12)
                .glassEffect(.clear, in: .rect(cornerRadius: cornerRadius, style: .continuous))
        } else {
            #if os(macOS)
            self
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.regularMaterial)
                )
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.22))
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 22, x: 0, y: 10)
            #else
            self
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
            #endif
        }
    }
}

public extension View {
    @ViewBuilder
    func monospacedDigitsCompat() -> some View {
        self.monospacedDigit()
    }

    /// Letter spacing where the platform has it, unchanged text where it does
    /// not. `tracking` arrived in iOS 16 / macOS 13, both above the deployment
    /// target, and the difference is cosmetic — small caps set a little tighter.
    @ViewBuilder
    func trackingCompat(_ amount: CGFloat) -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            self.tracking(amount)
        } else {
            self
        }
    }
}

public extension View {
    @ViewBuilder
    func compatOnChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            self.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value, perform: action)
        }
    }
}
