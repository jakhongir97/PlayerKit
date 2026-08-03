import SwiftUI

/// Adds non-gesture equivalents to the real video element.
///
/// The previous implementation exposed 1×1pt, 1%-opaque standalone elements.
/// They were impossible to target with Voice Control or Switch Control and
/// appeared detached from anything sighted users could identify. Named actions
/// on the visible video surface keep one honest focus target and still route
/// through the same level controller as touch and pointer input.
@MainActor
struct GestureAdjustmentAccessibilityActions: ViewModifier {
    let manager: GestureManager
    let geometry: GestureGeometry

    private func canAdjust(_ kind: GestureKind) -> Bool {
        manager.configuration.isEnabled
            && !manager.isLocked()
            && geometry.capabilities.availability(of: kind).isAvailable
    }

    func body(content: Content) -> some View {
        content
            .accessibilityActionIf(
                canAdjust(.volume),
                named: Text("Increase volume")
            ) { manager.nudge(.volume, .increment) }
            .accessibilityActionIf(
                canAdjust(.volume),
                named: Text("Decrease volume")
            ) { manager.nudge(.volume, .decrement) }
            .accessibilityActionIf(
                canAdjust(.brightness),
                named: Text("Increase brightness")
            ) { manager.nudge(.brightness, .increment) }
            .accessibilityActionIf(
                canAdjust(.brightness),
                named: Text("Decrease brightness")
            ) { manager.nudge(.brightness, .decrement) }
    }
}

extension View {
    @MainActor
    func gestureAdjustmentAccessibilityActions(
        manager: GestureManager,
        geometry: GestureGeometry
    ) -> some View {
        modifier(
            GestureAdjustmentAccessibilityActions(
                manager: manager,
                geometry: geometry
            )
        )
    }

    @ViewBuilder
    @MainActor
    func accessibilityActionIf(
        _ condition: Bool,
        named name: Text,
        action: @escaping () -> Void
    ) -> some View {
        if condition {
            accessibilityAction(named: name, action)
        } else {
            self
        }
    }
}
