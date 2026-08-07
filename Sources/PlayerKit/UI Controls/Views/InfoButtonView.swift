import SwiftUI

@MainActor
struct InfoButtonView: View {
    @ObservedObject private var playerManager: PlayerManager
    #if os(macOS)
    @Environment(\.openPlaybackDiagnostics) private var openPlaybackDiagnostics
    #endif

    @State private var showPopover = false
    
    init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
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
            .accessibilityLabel(playerManager.strings.streamingInformation)
            .accessibilityHint(playerManager.strings.streamingInformationHint)
            // The native presentation chooses a popover where space permits
            // and adapts to a compact presentation on narrow iPhone/Slide Over
            // surfaces. No orientation or device-class offsets to maintain.
            .popover(isPresented: $showPopover, arrowEdge: .leading) {
                StreamingInfoView(playerManager: playerManager)
                    .frame(minWidth: 240, idealWidth: 300, maxWidth: 360)
                    .padding(8)
            }
        #endif
    }

    private var infoButton: some View {
        Button(action: {
            #if os(macOS)
            if openPlaybackDiagnostics.isAvailable {
                openPlaybackDiagnostics()
            } else {
                showPopover.toggle()
            }
            #else
            showPopover.toggle()
            #endif
        }) {
            Image(systemName: "info")
                .playerControlIcon(appearance: playerManager.appearance)
        }
        .buttonStyle(PlayerControlButtonStyle())
        .accessibilityIdentifier("player.info")
    }
}
