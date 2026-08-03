import SwiftUI

@MainActor
struct MediaOptionsMenu: View {
    @StateObject private var viewModel: MediaOptionsMenuViewModel
    private let playerManager: PlayerManager

    private let insets = EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
    
    init(playerManager: PlayerManager = .shared) {
        self.playerManager = playerManager
        _viewModel = StateObject(wrappedValue: MediaOptionsMenuViewModel(playerManager: playerManager))
    }

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer {
                HStack {
                    PlaybackSpeedMenu(playerManager: playerManager)

                    if viewModel.hasSubtitles {
                        SubtitleMenu(playerManager: playerManager)
                    }

                    if viewModel.hasAudioTracks {
                        AudioMenu(playerManager: playerManager)
                    }
                }
                .padding(insets)
                .contentShape(Capsule())
            }
            .glassEffect(.clear, in: .capsule)
            .clipShape(Capsule())
            .buttonStyle(.plain)
            .transaction { $0.animation = nil }
        } else {
            fallback
        }
        #else
        fallback
        #endif
    }

    private var fallback: some View {
        HStack {
            PlaybackSpeedMenu(playerManager: playerManager)

            if viewModel.hasSubtitles { SubtitleMenu(playerManager: playerManager) }
            if viewModel.hasAudioTracks { AudioMenu(playerManager: playerManager) }
        }
        .padding(insets)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .contentShape(Capsule())
        .buttonStyle(.plain)
    }
}
