import SwiftUI

@MainActor
struct SharingMenuView: View {
    let playerManager: PlayerManager
    /// Mirrors `PlayerManager.isExternalPlaybackEnabled`. When AirPlay video
    /// routing is disabled there is nothing for the picker to do, so the
    /// affordance is withheld instead of being offered as a no-op.
    var isAirPlayEnabled: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            #if canImport(UIKit) && canImport(GoogleCast)
            CastButton(playerManager: playerManager)
                .playerControlIcon(appearance: playerManager.appearance)
            #endif

            if isAirPlayEnabled {
                AirPlayButton(playerManager: playerManager)
            }
        }
        #if os(macOS)
        .accessibilityElement(children: .contain)
        #endif
    }
}
