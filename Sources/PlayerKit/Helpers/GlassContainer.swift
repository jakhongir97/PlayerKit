import SwiftUI

/// MARK: - Glass background for the capsule container
struct GlassCapsuleBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.clear, in: .capsule)
        } else if #available(iOS 15.0, *) {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.12)))
        } else {
            content
                .background(
                    BlurView(style: .systemThinMaterial) // iOS 13/14 fallback
                        .clipShape(Capsule())
                )
                .overlay(Capsule().stroke(Color.white.opacity(0.12)))
        }
    }
}

// iOS 13/14 blur fallback
private struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemThinMaterial
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}
