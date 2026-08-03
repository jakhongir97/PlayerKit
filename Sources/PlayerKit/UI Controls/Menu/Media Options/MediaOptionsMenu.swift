import SwiftUI

@MainActor
struct MediaOptionsMenu: View {
    @StateObject private var viewModel: MediaOptionsMenuViewModel
    @ObservedObject private var playerManager: PlayerManager
    private let presentationPolicy: PlayerPresentationPolicy

    private let insets = EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
    
    init(
        playerManager: PlayerManager = .shared,
        presentationPolicy: PlayerPresentationPolicy = .init()
    ) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
        _viewModel = StateObject(wrappedValue: MediaOptionsMenuViewModel(playerManager: playerManager))
        self.presentationPolicy = presentationPolicy
    }

    var body: some View {
        if hasVisibleOptions {
            #if compiler(>=6.2)
            if #available(iOS 26.0, macOS 26.0, *) {
                GlassEffectContainer {
                    HStack {
                        if presentationPolicy.showsPlaybackQualityControl,
                           !playerManager.availablePlaybackQualityPresets.isEmpty {
                            PlaybackQualityMenu(playerManager: playerManager)
                        }

                        if presentationPolicy.showsPlaybackSpeedControl {
                            PlaybackSpeedMenu(playerManager: playerManager)
                        }

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
    }

    private var fallback: some View {
        HStack {
            if presentationPolicy.showsPlaybackQualityControl,
               !playerManager.availablePlaybackQualityPresets.isEmpty {
                PlaybackQualityMenu(playerManager: playerManager)
            }

            if presentationPolicy.showsPlaybackSpeedControl {
                PlaybackSpeedMenu(playerManager: playerManager)
            }

            if viewModel.hasSubtitles { SubtitleMenu(playerManager: playerManager) }
            if viewModel.hasAudioTracks { AudioMenu(playerManager: playerManager) }
        }
        .padding(insets)
        .thinMaterialBackgroundCompat(in: Capsule())
        .overlay(
            Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .contentShape(Capsule())
        .buttonStyle(.plain)
    }

    private var hasVisibleOptions: Bool {
        Self.hasVisibleOptions(
            presentationPolicy: presentationPolicy,
            hasPlaybackQualities: !playerManager.availablePlaybackQualityPresets.isEmpty,
            hasSubtitles: viewModel.hasSubtitles,
            hasAudioTracks: viewModel.hasAudioTracks
        )
    }

    static func hasVisibleOptions(
        presentationPolicy: PlayerPresentationPolicy,
        hasPlaybackQualities: Bool,
        hasSubtitles: Bool,
        hasAudioTracks: Bool
    ) -> Bool {
        presentationPolicy.showsPlaybackSpeedControl
            || (presentationPolicy.showsPlaybackQualityControl && hasPlaybackQualities)
            || hasSubtitles
            || hasAudioTracks
    }
}

@MainActor
private struct PlaybackQualityMenu: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        Menu {
            Section(header: Text(playerManager.strings.playbackQualityTitle)) {
                ForEach(playerManager.availablePlaybackQualityPresets) { preset in
                    Button {
                        playerManager.selectPlaybackQualityPreset(preset)
                    } label: {
                        HStack {
                            Text(title(for: preset))
                            if playerManager.selectedPlaybackQualityPreset == preset {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .padding(10)
        }
        .accessibilityLabel(playerManager.strings.playbackQualityAccessibilityLabel)
        .accessibilityHint(playerManager.strings.playbackQualityHint)
        .accessibilityIdentifier("player.qualityMenu")
        .buttonStyle(.plain)
        .onTapGesture {
            playerManager.userInteracted()
        }
    }

    private func title(for preset: PlaybackQualityPreset) -> String {
        switch preset {
        case .automatic: return playerManager.strings.automaticQuality
        case .maximum: return playerManager.strings.maximumQuality
        case .optimal: return playerManager.strings.optimalQuality
        case .minimum: return playerManager.strings.minimumQuality
        }
    }
}
