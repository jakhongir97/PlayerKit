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
            .animation(PlayerChromeMotion.hover, value: isHovering)
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

public extension View {
    /// The chrome's only hover treatment.
    ///
    /// The scale defaults to the shared token rather than to a literal: four
    /// call sites previously passed four different values, so neighbouring
    /// controls grew by different amounts under the same cursor.
    @ViewBuilder
    func desktopHoverLift(
        enabled: Bool = true,
        scale: CGFloat = PlayerChromeMotion.hoverScale
    ) -> some View {
        modifier(DesktopHoverLiftModifier(enabled: enabled, scale: scale))
    }
}
