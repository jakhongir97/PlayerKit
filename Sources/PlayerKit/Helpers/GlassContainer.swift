import SwiftUI

// MARK: - Modifier
private struct GlassMenuPill: ViewModifier {
    var insets: EdgeInsets
    var height: CGFloat = 36

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer() {
                content
                    .padding(insets)
                    .frame(height: height)     // stable geometry during Menu rehost
                    .contentShape(Capsule())   // stable hit area
                    .buttonStyle(.plain)
            }
            .transaction { $0.animation = nil } // prevent one-frame morph
        } else {
            content
                .padding(insets)
                .frame(height: height)
                //.background(.ultraThinMaterial, in: Capsule())
                .contentShape(Capsule())
                .buttonStyle(.plain)
        }
    }
}

public extension View {
    /// Group controls into a capsule with proper glass handling on iOS 26+ and safe fallback below.
    func glassMenuPill(insets: EdgeInsets = EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8),
                       height: CGFloat = 36) -> some View {
        modifier(GlassMenuPill(insets: insets, height: height))
    }
}

