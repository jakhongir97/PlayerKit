import SwiftUI

struct InfoButtonView: View {
    private let playerManager: PlayerManager
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass

    @State private var showPopover = false
    
    init(playerManager: PlayerManager = .shared) {
        self.playerManager = playerManager
    }

    // Determine landscape orientation based on size classes.
    // On an iPhone:
    //  - Portrait: verticalSizeClass = .regular, horizontalSizeClass = .compact
    //  - Landscape: verticalSizeClass = .compact
    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        Button(action: {
            withAnimation(.spring()) {
                showPopover.toggle()
            }
        }) {
            Image(systemName: "info")
                .circularGlassIcon()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Streaming information")
        .accessibilityHint("Shows bitrate, buffer, frame rate and resolution")
        .accessibilityIdentifier("player.info")
        .overlay(
            Group {
                if showPopover {
                    StreamingInfoView(playerManager: playerManager)
                        .frame(width: 200)
                        .offset(
                            x: isLandscape ? 60 : 0,
                            y: isLandscape ? 0 : -110
                        )
                        .transition(.opacity)
                        .zIndex(1)
                }
            },
            alignment: .leading
        )
    }
}
