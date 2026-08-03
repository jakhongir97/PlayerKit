import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// MARK: - Glass background for the capsule container
struct GlassCapsuleBackground: ViewModifier {
    func body(content: Content) -> some View {
        // The former middle tier tested `iOS 15.0 / macOS 12.0`, which is at or
        // below the package's deployment target and therefore always true —
        // making the `else` branch unreachable. Collapsing it also clears the
        // "ViewBuilder does not implement buildLimitedAvailability; this code
        // may crash on earlier versions of the OS" warning the ladder produced.
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.clear, in: .capsule)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12)))
    }
}

#if canImport(UIKit)
private struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemThinMaterial

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}
#else
private struct BlurView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
#endif
