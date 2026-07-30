import SwiftUI

struct SharingMenuView: View {
    /// Mirrors `PlayerManager.isExternalPlaybackEnabled`. When AirPlay video
    /// routing is disabled there is nothing for the picker to do, so the
    /// affordance is withheld instead of being offered as a no-op.
    var isAirPlayEnabled: Bool = false

    var body: some View {
        CastButton(isAirPlayEnabled: isAirPlayEnabled)
        #if !os(macOS)
            .circularGlassIcon()
        #endif
    }
}
