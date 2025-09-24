import SwiftUI

struct MediaOptionsMenu: View {
    @StateObject private var viewModel = MediaOptionsMenuViewModel()

    private let insets = EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                HStack {
                    PlaybackSpeedMenu()

                    if viewModel.hasSubtitles {
                        SubtitleMenu()
                    }

                    if viewModel.hasAudioTracks {
                        AudioMenu()
                    }
                }
                .padding(insets)
                .contentShape(Capsule())
            }
            .glassEffect(.clear, in: .capsule)
            .clipShape(Capsule())
            .transaction { $0.animation = nil }
        } else if #available(iOS 15.0, *) {
            // iOS 15–25: material-based "glass"
            HStack {
                PlaybackSpeedMenu()

                if viewModel.hasSubtitles { SubtitleMenu() }
                if viewModel.hasAudioTracks { AudioMenu() }
            }
            .padding(insets)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Capsule())
        } else {
            // Very old fallback
            HStack {
                PlaybackSpeedMenu()

                if viewModel.hasSubtitles { SubtitleMenu() }
                if viewModel.hasAudioTracks { AudioMenu() }
            }
            .padding(insets)
            .background(Color.white.opacity(0.10))
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
    }
}
