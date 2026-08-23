import SwiftUI

/// An action the embedding app contributes to the player's top bar.
///
/// Hosts used to reach for this by pinning their own button over the chrome at
/// a hand-measured offset — iTV's "more" disc sat 124pt in from the trailing
/// edge, a number that was correct for exactly one arrangement of the bar and
/// silently wrong for the next. The host cannot know where PlayerKit's
/// controls are, and should not have to: it declares *what* it offers and the
/// bar decides where that goes, with the same glass, the same hit target, the
/// same auto-hide and the same lock gating as every control beside it.
///
/// Actions render inside one overflow menu (an ellipsis disc), so a host
/// contributing four actions costs the bar exactly one slot. A nested
/// ``PlayerHostAction/submenu(id:title:image:children:)`` becomes a submenu.
public struct PlayerHostAction: Identifiable {
    /// What the row does when chosen.
    public enum Kind {
        /// Runs on the main actor when the row is tapped.
        case action(@MainActor () -> Void)
        /// Opens a nested menu of these rows. An empty list renders nothing.
        case submenu([PlayerHostAction])
    }

    /// Stable across rebuilds of the host's list, so SwiftUI can diff the menu
    /// rather than tearing it down.
    public let id: String
    public var title: String
    /// An optional leading glyph. Hosts with `UIImage` assets wrap them with
    /// `Image(uiImage:)`; `systemName` initialisers cover SF Symbols.
    public var image: Image?
    /// A disabled row stays visible but cannot be chosen, which is how the
    /// system menus show an action that applies to this content but not now.
    public var isEnabled: Bool
    public var kind: Kind

    public init(
        id: String,
        title: String,
        image: Image? = nil,
        isEnabled: Bool = true,
        kind: Kind
    ) {
        self.id = id
        self.title = title
        self.image = image
        self.isEnabled = isEnabled
        self.kind = kind
    }

    /// A plain row that runs `handler`.
    public init(
        id: String,
        title: String,
        image: Image? = nil,
        isEnabled: Bool = true,
        handler: @escaping @MainActor () -> Void
    ) {
        self.init(id: id, title: title, image: image, isEnabled: isEnabled, kind: .action(handler))
    }

    /// A plain row with an SF Symbol glyph.
    public init(
        id: String,
        title: String,
        systemImage: String,
        isEnabled: Bool = true,
        handler: @escaping @MainActor () -> Void
    ) {
        self.init(
            id: id,
            title: title,
            image: Image(systemName: systemImage),
            isEnabled: isEnabled,
            handler: handler
        )
    }

    /// A row that opens a nested menu.
    public static func submenu(
        id: String,
        title: String,
        image: Image? = nil,
        isEnabled: Bool = true,
        children: [PlayerHostAction]
    ) -> PlayerHostAction {
        PlayerHostAction(id: id, title: title, image: image, isEnabled: isEnabled, kind: .submenu(children))
    }

    /// Whether the row contributes anything to a rendered menu.
    ///
    /// A submenu with no children is dropped rather than shown as a dead row,
    /// and a menu consisting only of such rows is no menu at all — which is what
    /// lets the bar withhold the ellipsis disc instead of offering an empty one.
    public var isPresentable: Bool {
        switch kind {
        case .action:
            return true
        case .submenu(let children):
            return children.contains { $0.isPresentable }
        }
    }
}

extension Array where Element == PlayerHostAction {
    /// The rows worth rendering. See ``PlayerHostAction/isPresentable``.
    public var presentable: [PlayerHostAction] {
        filter { $0.isPresentable }
    }
}
