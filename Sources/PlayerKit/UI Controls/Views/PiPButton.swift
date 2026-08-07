import SwiftUI

@MainActor
struct PiPButton: View {
    @ObservedObject var playerManager: PlayerManager
    /// Inside a shared bar capsule the glyph must not bring a disc of its own.
    let isGrouped: Bool

    init(playerManager: PlayerManager = .shared, isGrouped: Bool = false) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
        self.isGrouped = isGrouped
    }

    var body: some View {
        Button(action: {
            if playerManager.isPiPActive {
                playerManager.stopPiP()
            } else {
                playerManager.startPiP()
            }
        }) {
            Image(systemName: playerManager.isPiPActive ? "pip.fill" : "pip")
                .playerBarItem(
                    isGrouped: isGrouped,
                    appearance: playerManager.appearance,
                    hoverEnabled: playerManager.canTogglePiP
                )
                .playerControlEnabled(playerManager.canTogglePiP)
        }
        // Grouped, the glyph owns the hover response — see FullscreenButtonView.
        .buttonStyle(
            PlayerControlButtonStyle(hoverEnabled: !isGrouped && playerManager.canTogglePiP)
        )
        .disabled(!playerManager.canTogglePiP)
        .accessibilityLabel(
            playerManager.isPiPActive
                ? playerManager.strings.stopPictureInPicture
                : playerManager.strings.startPictureInPicture
        )
        .accessibilityHint(playerManager.strings.pictureInPictureHint)
        .accessibilityIdentifier("player.pip")
    }
}

extension View {
    /// A bar icon: bare when it shares a group's surface, on its own disc when
    /// it stands alone.
    ///
    /// `hoverEnabled` only reaches the grouped glyph — a standalone disc's
    /// hover belongs to its `PlayerControlButtonStyle`, same as every other
    /// solo control.
    @ViewBuilder
    func playerBarItem(
        isGrouped: Bool,
        appearance: PlayerAppearance,
        hoverEnabled: Bool = true
    ) -> some View {
        if isGrouped {
            playerBarGlyph(hoverEnabled: hoverEnabled)
        } else {
            playerControlIcon(appearance: appearance)
        }
    }
}
