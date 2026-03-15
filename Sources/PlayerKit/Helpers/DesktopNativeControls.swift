import SwiftUI

#if os(macOS)
import AppKit
#endif

private struct DesktopHoverLiftModifier: ViewModifier {
    var enabled: Bool
    var scale: CGFloat

    @State private var isHovering = false

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .scaleEffect(enabled && isHovering ? scale : 1)
            .offset(y: enabled && isHovering ? -1 : 0)
            .shadow(
                color: .black.opacity(enabled && isHovering ? 0.30 : 0.18),
                radius: enabled && isHovering ? 18 : 10,
                x: 0,
                y: enabled && isHovering ? 10 : 5
            )
            .animation(.easeOut(duration: 0.16), value: isHovering)
            .onHover { hovering in
                guard enabled else {
                    isHovering = false
                    return
                }
                isHovering = hovering
            }
        #else
        content
        #endif
    }
}

private struct DesktopToolbarCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .background(
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
            )
            .background(
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.18))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.24), radius: 22, x: 0, y: 10)
        #else
        content
        #endif
    }
}

public extension View {
    @ViewBuilder
    func desktopHoverLift(enabled: Bool = true, scale: CGFloat = 1.04) -> some View {
        modifier(DesktopHoverLiftModifier(enabled: enabled, scale: scale))
    }

    @ViewBuilder
    func desktopToolbarCapsule() -> some View {
        modifier(DesktopToolbarCapsuleModifier())
    }
}
