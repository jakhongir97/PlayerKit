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
        #if os(macOS)
        infoButton
            .help("Playback status")
            .accessibilityLabel("Playback status")
            .accessibilityHint("Shows playback quality and details you can copy for support")
            .popover(isPresented: $showPopover, arrowEdge: .leading) {
                HLSPlaybackDiagnosticsView(playerManager: playerManager)
            }
        #else
        infoButton
            .accessibilityLabel("Streaming information")
            .accessibilityHint("Shows bitrate, buffer, frame rate and resolution")
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
        #endif
    }

    private var infoButton: some View {
        Button(action: {
            #if os(macOS)
            showPopover.toggle()
            #else
            withAnimation(.spring()) {
                showPopover.toggle()
            }
            #endif
        }) {
            Image(systemName: "info")
                .circularGlassIcon()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("player.info")
    }
}
