import SwiftUI

@MainActor
struct MediaOptionsMenu: View {
    @StateObject private var viewModel: MediaOptionsMenuViewModel
    @ObservedObject private var playerManager: PlayerManager
    private let presentationPolicy: PlayerPresentationPolicy

    init(
        playerManager: PlayerManager = .shared,
        presentationPolicy: PlayerPresentationPolicy = .init()
    ) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
        _viewModel = StateObject(wrappedValue: MediaOptionsMenuViewModel(playerManager: playerManager))
        self.presentationPolicy = presentationPolicy
    }

    /// One pill, one height, one surface.
    ///
    /// The 26+ and pre-26 paths used to be two separate bodies that had drifted
    /// apart — different padding, one with a stroke and one without — so the
    /// same pill was a different size depending on the OS. They now differ only
    /// in the finish `playerGlass` applies, and the row height comes from the
    /// shared bar metric so this pill lines up with the live badge and the
    /// trailing icon group instead of standing ~12pt taller than both.
    var body: some View {
        if hasVisibleOptions {
            PlayerGlassGroup {
                HStack(spacing: PlayerChromeMetrics.spacingXS) {
                    if presentationPolicy.showsPlaybackQualityControl,
                       !playerManager.availablePlaybackQualityPresets.isEmpty {
                        PlaybackQualityMenu(playerManager: playerManager)
                    }

                    if presentationPolicy.showsPlaybackSpeedControl {
                        PlaybackSpeedMenu(playerManager: playerManager)
                    }

                    if presentationPolicy.showsMediaTrackControls,
                       viewModel.hasSubtitles {
                        SubtitleMenu(playerManager: playerManager)
                    }

                    if presentationPolicy.showsMediaTrackControls,
                       viewModel.hasAudioTracks {
                        AudioMenu(playerManager: playerManager)
                    }
                }
                .padding(.horizontal, PlayerChromeMetrics.spacingS)
                .frame(minHeight: PlayerChromeMetrics.barItemHeight)
                .playerSurfaceShape(.capsule)
                .playerGlass(.capsule, prominence: .bar, appearance: playerManager.appearance)
                .buttonStyle(.plain)
            }
        }
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
            || (presentationPolicy.showsMediaTrackControls
                && (hasSubtitles || hasAudioTracks))
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
                .playerBarGlyph()
        }
        .hidesMenuIndicatorCompat()
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
