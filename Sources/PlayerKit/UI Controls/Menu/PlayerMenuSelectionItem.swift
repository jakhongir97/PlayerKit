import SwiftUI

/// One choice in a bottom-bar options menu, drawn as a checked menu item.
///
/// The rows used to be `Button { HStack { Text; if selected { checkmark } } }`.
/// On macOS SwiftUI bridges that conditional image into the `NSMenuItem`, and
/// once the item's image changes while the player keeps re-rendering, the menu
/// window is sized from a stale measurement: pick the last subtitle track and
/// the menu reopens as a 44pt column reading "…", "r", "✓ i". A `Toggle` maps
/// to the item's native checked state instead, so no item changes shape and
/// the width holds. It is the same checkmark row on iOS, available since 14.
///
/// Do not swap this for an always-present checkmark faded with `opacity` —
/// menus ignore opacity and draw the mark on every row.
struct PlayerMenuSelectionItem: View {
    let title: String
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Toggle(isOn: Self.selectionBinding(isSelected: isSelected, select: select)) {
            Text(title)
        }
    }

    /// A menu row is a choice, not a switch. Clicking the row that is already
    /// checked asks the toggle to turn off; treat every click as "choose this"
    /// instead, exactly as the old `Button` did — re-applying the current choice
    /// never clears it, and the select paths end in `userInteracted()`, so the
    /// click still restarts the chrome's auto-hide timer.
    static func selectionBinding(
        isSelected: Bool,
        select: @escaping () -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { isSelected },
            set: { _ in select() }
        )
    }
}
