import SwiftUI

struct SharingMenuView: View {
    var body: some View {
        CastButton()
        #if !os(macOS)
            .circularGlassIcon()
        #endif
    }
}
