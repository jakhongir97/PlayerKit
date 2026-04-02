import SwiftUI

struct SkipIntroButtonView: View {
    @ObservedObject var playerManager: PlayerManager

    @State private var isGlowActive = false

    private let fallbackIntroTargetSeconds = 85.0
    private let minimumEpisodeDurationSeconds = 8 * 60.0
    private let minimumRemainingDurationSeconds = 2 * 60.0

    init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
    }

    var body: some View {
        if let introTargetSeconds,
           shouldShowButton(targetTime: introTargetSeconds) {
            Button {
                playerManager.userInteracted()
                playerManager.seek(to: introTargetSeconds)
            } label: {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    glowColor.opacity(isGlowActive ? 0.34 : 0.20),
                                    glowColor.opacity(0.10),
                                    .clear,
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 52)
                        .padding(.horizontal, -8)
                        .blur(radius: isGlowActive ? 14 : 10)
                        .scaleEffect(isGlowActive ? 1.02 : 0.98)

                    HStack(spacing: 8) {
                        Image(systemName: "goforward")
                            .font(.system(size: 12, weight: .bold))

                        Text("Skip Intro")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(buttonBackground)
                    .overlay(buttonStroke)
                    .shadow(color: glowColor.opacity(isGlowActive ? 0.30 : 0.18), radius: 20, x: 0, y: 0)
                }
            }
            .buttonStyle(.plain)
            .desktopHoverLift(enabled: true, scale: 1.02)
            .animation(
                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                value: isGlowActive
            )
            .onAppear {
                isGlowActive = true
            }
            .accessibilityLabel("Skip Intro")
            .accessibilityHint("Skips the opening section of this episode")
            .accessibilityIdentifier("player.skipIntro")
        }
    }

    private var introTargetSeconds: Double? {
        guard playerManager.contentType == .episode else {
            return nil
        }

        let duration = resolvedDuration
        guard duration >= minimumEpisodeDurationSeconds else {
            return nil
        }

        let inferredTarget = duration.isFinite && duration > 0
            ? min(max(duration * 0.02, 45), 95)
            : fallbackIntroTargetSeconds

        let upperBound = max(duration - minimumRemainingDurationSeconds, fallbackIntroTargetSeconds)
        return min(inferredTarget, upperBound)
    }

    private var resolvedDuration: Double {
        let duration = playerManager.duration
        if duration.isFinite && duration > 0 {
            return duration
        }

        return fallbackIntroTargetSeconds + minimumRemainingDurationSeconds + 1
    }

    private var glowColor: Color {
        Color(red: 0.30, green: 0.67, blue: 1.0)
    }

    @ViewBuilder
    private var buttonBackground: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(.clear)
                .glassEffect(.clear, in: .capsule)
        } else if #available(iOS 15.0, macOS 12.0, *) {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
        } else {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.12))
        }
    }

    private var buttonStroke: some View {
        Capsule(style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        glowColor.opacity(0.85),
                        Color.white.opacity(0.52),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: 1
            )
    }

    private func shouldShowButton(targetTime: Double) -> Bool {
        let currentTime = max(playerManager.currentTime, 0)
        return currentTime < max(targetTime - 1, 1)
    }
}
