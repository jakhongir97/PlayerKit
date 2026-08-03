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
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
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
        .thinMaterialBackgroundCompat(in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
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
            .playbackActionButtonStyleCompat(prominent: true)
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
        .playbackActionButtonStyleCompat(prominent: false)
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
            .thinMaterialBackgroundCompat(in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
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
            .playbackActionButtonStyleCompat(prominent: true)
            .accessibilityIdentifier("player.replay")

        Button(playerManager.strings.close) {
            playerManager.shouldDismiss = true
        }
        .playbackActionButtonStyleCompat(prominent: false)
        .accessibilityIdentifier("player.endClose")
    }
}

private extension View {
    @ViewBuilder
    func playbackActionButtonStyleCompat(prominent: Bool) -> some View {
        if #available(iOS 15.0, macOS 12.0, *) {
            if prominent {
                self.buttonStyle(.borderedProminent).controlSize(.large)
            } else {
                self.buttonStyle(.bordered).controlSize(.large)
            }
        } else {
            self.buttonStyle(PlaybackActionFallbackButtonStyle(prominent: prominent))
        }
    }
}

private struct PlaybackActionFallbackButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundColor(prominent ? .white : .accentColor)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(prominent ? Color.accentColor : Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(prominent ? 0 : 0.18), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
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
