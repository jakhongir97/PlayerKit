import SwiftUI

/// Adjustable elements for the gestures that have no button.
///
/// Volume and brightness were reachable *only* by swiping, which meant they did
/// not exist for anyone using VoiceOver, Switch Control or Voice Control. These
/// are 1×1pt focusable proxies carrying the standard adjustable trait, so the
/// rotor's swipe-up/swipe-down does exactly what the rail does.
///
/// A side whose capability is unavailable contributes no element at all — an
/// accessibility control that silently does nothing is worse than its absence.
struct GestureAccessibilityProxies: View {

    let manager: GestureManager
    let geometry: GestureGeometry

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RailSide.allCases, id: \.self) { side in
                if let kind = geometry.kind(forSide: side),
                   geometry.capabilities.availability(of: kind).isAvailable {
                    proxy(for: kind)
                }
            }
        }
        .frame(width: 1, height: 1)
        .opacity(0.01)
    }

    private func proxy(for kind: GestureKind) -> some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel(kind == .brightness ? "Brightness" : "Volume")
            .accessibilityValue("\(Int((manager.level(of: kind) * 100).rounded())) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: manager.nudge(kind, .increment)
                case .decrement: manager.nudge(kind, .decrement)
                @unknown default: break
                }
            }
    }
}
