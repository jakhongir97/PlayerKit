import SwiftUI

struct BufferingIndicatorView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        if playerManager.isBuffering {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .padding(.horizontal, 10)
        }
    }
}

