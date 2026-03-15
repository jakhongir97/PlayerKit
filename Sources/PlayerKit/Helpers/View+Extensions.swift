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
                    print("Failed to set orientation: \(error)")
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
    func hierarchicalSymbolRendering() -> some View {
        if #available(iOS 15.0, macOS 12.0, *) {
            self.symbolRenderingMode(.hierarchical)
        } else {
            self
        }
    }
}

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

extension View {
    @ViewBuilder
    func compatTint(_ color: Color) -> some View {
        if #available(iOS 15.0, macOS 12.0, *) {
            self.tint(color)
        } else {
            self.accentColor(color)
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
        } else if #available(iOS 15.0, macOS 12.0, *) {
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
        } else {
            self
                .padding(12)
                .background(Color.black.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

public extension View {
    @ViewBuilder
    func monospacedDigitsCompat() -> some View {
        if #available(iOS 15.0, macOS 12.0, *) {
            self.monospacedDigit()
        } else {
            self.font(.system(.caption, design: .monospaced))
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
