import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// MARK: - Glass background for the capsule container
///
/// Kept as a named modifier because the scrubber and several bar pills read
/// better as a declaration than as a `playerGlass` call inline, but it is the
/// same surface — there is no second capsule recipe in the chrome any more.
struct GlassCapsuleBackground: ViewModifier {
    var prominence: PlayerSurfaceProminence = .bar
    var appearance: PlayerAppearance = .default

    func body(content: Content) -> some View {
        content.playerGlass(.capsule, prominence: prominence, appearance: appearance)
    }
}

/// Groups sibling glass surfaces so the platform can merge and morph them.
///
/// Apple's guidance is that related glass elements belong in one container:
/// separate `glassEffect` calls each sample the backdrop independently and
/// read as unrelated blobs, while a container lets neighbouring controls share
/// one lensing pass and blend as they move together. Pre-26 this is a plain
/// passthrough, which is why every call site can use it unconditionally.
struct PlayerGlassGroup<Content: View>: View {
    var spacing: CGFloat = PlayerChromeMetrics.spacingS
    @ViewBuilder var content: Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
        #else
        content
        #endif
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
