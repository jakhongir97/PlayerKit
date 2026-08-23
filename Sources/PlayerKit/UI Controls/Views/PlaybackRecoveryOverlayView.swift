import SwiftUI

@MainActor
struct PlaybackRecoveryOverlayView: View {
    @ObservedObject var playerManager: PlayerManager
    @Environment(\.sizeCategory) private var sizeCategory
    let error: PlayerKitError

    private var presentation: PlaybackErrorPresentation {
        PlaybackErrorPresentation(
            error,
            terminalPlaybackFailure: playerManager.isPlaybackErrorTerminal,
            strings: playerManager.strings
        )
    }

    var body: some View {
        Group {
            if presentation.blocksPlayback {
                ZStack {
                    Color.black.opacity(0.55)
                        .contentShape(Rectangle())

                    card
                        .padding(24)
                }
            } else {
                VStack {
                    card
                        .padding(.horizontal, PlayerChromeMetrics.spacingL)
                        // Below the top bar, not on top of it. Pinned at 16pt
                        // this card covered the close and lock discs, so a
                        // recoverable error took the way out with it.
                        .padding(.top, PlayerChromeMetrics.minimumHitTarget
                                 + (PlayerChromeMetrics.spacingL * 2))
                    Spacer()
                }
            }
        }
        .accessibilityIdentifier("player.errorOverlay")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(presentation.title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundColor(.white)

            Text(presentation.message)
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            if Self.stacksActions(for: sizeCategory) {
                VStack(alignment: .leading, spacing: 12) {
                    actionButtons
                }
            } else {
                HStack(spacing: 12) {
                    actionButtons
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 520, alignment: .leading)
        .thinMaterialBackgroundCompat(in: RoundedRectangle(cornerRadius: PlayerChromeMetrics.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PlayerChromeMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if presentation.isRetryable {
            Button(action: playerManager.retryPlayback) {
                if playerManager.isRetryingPlayback {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(playerManager.strings.refreshing)
                    }
                } else {
                    Text(playerManager.strings.retry)
                }
            }
            .playbackActionPill(prominent: true, appearance: playerManager.appearance)
            .disabled(playerManager.isRetryingPlayback)
            .accessibilityIdentifier("player.errorRetry")
        }

        Button(
            presentation.blocksPlayback
                ? playerManager.strings.close
                : playerManager.strings.dismiss
        ) {
            if presentation.blocksPlayback {
                playerManager.shouldDismiss = true
            } else {
                playerManager.clearError()
            }
        }
        .playbackActionPill(prominent: false, appearance: playerManager.appearance)
        .accessibilityIdentifier(
            presentation.blocksPlayback ? "player.errorClose" : "player.errorDismiss"
        )
    }

    static func stacksActions(for size: ContentSizeCategory) -> Bool {
        size.isAccessibilityCategory
    }
}

@MainActor
struct PlaybackEndedOverlayView: View {
    @ObservedObject var playerManager: PlayerManager
    @Environment(\.sizeCategory) private var sizeCategory

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .contentShape(Rectangle())

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.white)
                    .accessibilityHidden(true)

                Text(playerManager.strings.playbackFinished)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)

                if PlaybackRecoveryOverlayView.stacksActions(for: sizeCategory) {
                    VStack(spacing: 12) {
                        endButtons
                    }
                } else {
                    HStack(spacing: 12) {
                        endButtons
                    }
                }
            }
            .padding(24)
            .thinMaterialBackgroundCompat(in: RoundedRectangle(cornerRadius: PlayerChromeMetrics.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PlayerChromeMetrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            .padding(24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.endOverlay")
    }

    @ViewBuilder
    private var endButtons: some View {
        Button(playerManager.strings.replay, action: playerManager.replay)
            .playbackActionPill(prominent: true, appearance: playerManager.appearance)
            .accessibilityIdentifier("player.replay")

        Button(playerManager.strings.close) {
            playerManager.shouldDismiss = true
        }
        .playbackActionPill(prominent: false, appearance: playerManager.appearance)
        .accessibilityIdentifier("player.endClose")
    }
}

private extension View {
    /// The overlay actions wear the chrome's own pills.
    ///
    /// They used to be `.borderedProminent` / `.bordered`, which paint with
    /// whatever `tintColor` the host's window carries — iTV's is a bright
    /// green under a white label, ~1.8:1 — and ignore ``PlayerAppearance``
    /// entirely, the one styling hook the design gives a host. The prominent
    /// pill is the same surface as the skip-intro pill; the secondary one is
    /// the bar surface every other capsule in the chrome sits on.
    func playbackActionPill(prominent: Bool, appearance: PlayerAppearance) -> some View {
        buttonStyle(PlaybackActionPillStyle(prominent: prominent, appearance: appearance))
    }
}

private struct PlaybackActionPillStyle: ButtonStyle {
    let prominent: Bool
    let appearance: PlayerAppearance

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .playerChromeFont(.action)
            .foregroundColor(prominent ? appearance.accentForeground : .white)
            .padding(.horizontal, PlayerChromeMetrics.pillHorizontalPadding)
            .frame(minHeight: PlayerChromeMetrics.barItemHeight)
            .playerSurfaceShape(.capsule)
            .playerGlass(.capsule, prominence: prominent ? .prominent : .bar, appearance: appearance)
            .scaleEffect(configuration.isPressed ? PlayerChromeMotion.pressedScale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(PlayerChromeMotion.press, value: configuration.isPressed)
    }
}

struct PlaybackErrorPresentation: Equatable {
    let title: String
    let message: String
    let blocksPlayback: Bool
    let isRetryable: Bool

    init(
        _ error: PlayerKitError,
        terminalPlaybackFailure: Bool = false,
        strings: PlayerStrings = PlayerStrings()
    ) {
        switch error {
        case .mediaLoadFailed:
            title = strings.playbackUnavailableTitle
            message = strings.playbackUnavailableMessage
            blocksPlayback = true
            isRetryable = true

        case .unknown:
            title = strings.actionUnavailableTitle
            message = strings.actionUnavailableMessage
            blocksPlayback = terminalPlaybackFailure
            isRetryable = terminalPlaybackFailure

        case .pictureInPictureFailed:
            title = strings.pictureInPictureUnavailableTitle
            message = strings.pictureInPictureUnavailableMessage
            blocksPlayback = terminalPlaybackFailure
            isRetryable = terminalPlaybackFailure

        case .castSessionUnavailable, .castURLMissing:
            title = strings.castingUnavailableTitle
            message = strings.castingUnavailableMessage
            blocksPlayback = terminalPlaybackFailure
            isRetryable = terminalPlaybackFailure

        case .externalPlaybackDeviceUnavailable,
             .externalPlaybackURLMissing,
             .externalPlaybackRequiresReachableURL,
             .externalPlaybackFailed:
            title = strings.externalPlaybackUnavailableTitle
            message = strings.externalPlaybackUnavailableMessage
            blocksPlayback = terminalPlaybackFailure
            isRetryable = terminalPlaybackFailure
        }
    }
}
