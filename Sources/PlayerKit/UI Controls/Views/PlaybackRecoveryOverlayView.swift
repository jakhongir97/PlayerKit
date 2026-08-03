import SwiftUI

@MainActor
struct PlaybackRecoveryOverlayView: View {
    @ObservedObject var playerManager: PlayerManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let error: PlayerKitError

    private var presentation: PlaybackErrorPresentation {
        PlaybackErrorPresentation(
            error,
            terminalPlaybackFailure: playerManager.isPlaybackErrorTerminal
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

            if Self.stacksActions(for: dynamicTypeSize) {
                VStack(alignment: .leading, spacing: 12) {
                    actionButtons
                }
                .controlSize(.large)
            } else {
                HStack(spacing: 12) {
                    actionButtons
                }
                .controlSize(.large)
            }
        }
        .padding(20)
        .frame(maxWidth: 520, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if presentation.isRetryable {
            Button(action: playerManager.retryPlayback) {
                if playerManager.isRetryingPlayback {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Refreshing…")
                    }
                } else {
                    Text("Retry")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(playerManager.isRetryingPlayback)
            .accessibilityIdentifier("player.errorRetry")
        }

        Button(presentation.blocksPlayback ? "Close" : "Dismiss") {
            if presentation.blocksPlayback {
                playerManager.shouldDismiss = true
            } else {
                playerManager.clearError()
            }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(
            presentation.blocksPlayback ? "player.errorClose" : "player.errorDismiss"
        )
    }

    static func stacksActions(for size: DynamicTypeSize) -> Bool {
        size.isAccessibilitySize
    }
}

@MainActor
struct PlaybackEndedOverlayView: View {
    @ObservedObject var playerManager: PlayerManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .contentShape(Rectangle())

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.white)
                    .accessibilityHidden(true)

                Text("Playback finished")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)

                if PlaybackRecoveryOverlayView.stacksActions(for: dynamicTypeSize) {
                    VStack(spacing: 12) {
                        endButtons
                    }
                    .controlSize(.large)
                } else {
                    HStack(spacing: 12) {
                        endButtons
                    }
                    .controlSize(.large)
                }
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            .padding(24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.endOverlay")
    }

    @ViewBuilder
    private var endButtons: some View {
        Button("Replay", action: playerManager.replay)
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("player.replay")

        Button("Close") {
            playerManager.shouldDismiss = true
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("player.endClose")
    }
}

struct PlaybackErrorPresentation: Equatable {
    let title: String
    let message: String
    let blocksPlayback: Bool
    let isRetryable: Bool

    init(_ error: PlayerKitError, terminalPlaybackFailure: Bool = false) {
        switch error {
        case .mediaLoadFailed:
            title = "Playback unavailable"
            message = "We couldn’t load this video. Check your connection and try again."
            blocksPlayback = true
            isRetryable = true

        case .unknown:
            title = "Action unavailable"
            message = "That action couldn’t be completed. You can keep watching here."
            blocksPlayback = terminalPlaybackFailure
            isRetryable = terminalPlaybackFailure

        case .pictureInPictureFailed:
            title = "Picture in Picture unavailable"
            message = "Picture in Picture couldn’t start. You can keep watching here."
            blocksPlayback = terminalPlaybackFailure
            isRetryable = terminalPlaybackFailure

        case .castSessionUnavailable, .castURLMissing:
            title = "Casting unavailable"
            message = "Casting isn’t available right now. You can keep watching on this device."
            blocksPlayback = terminalPlaybackFailure
            isRetryable = terminalPlaybackFailure

        case .externalPlaybackDeviceUnavailable,
             .externalPlaybackURLMissing,
             .externalPlaybackRequiresReachableURL,
             .externalPlaybackFailed:
            title = "External playback unavailable"
            message = "This video can’t play on the selected device. You can keep watching here."
            blocksPlayback = terminalPlaybackFailure
            isRetryable = terminalPlaybackFailure
        }
    }
}
