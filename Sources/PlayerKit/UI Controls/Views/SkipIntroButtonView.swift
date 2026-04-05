import SwiftUI

private enum SkipSegmentHeuristics {
    static let fallbackIntroTargetSeconds = 85.0
    static let fallbackOutroLeadSeconds = 55.0
    static let minimumEpisodeDurationSeconds = 8 * 60.0
    static let minimumRemainingDurationSeconds = 2 * 60.0
    static let minimumOutroRemainingSeconds = 4.0
}

struct SkipIntroButtonView: View {
    @ObservedObject var playerManager: PlayerManager

    init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
    }

    var body: some View {
        if let introTargetSeconds,
           shouldShowButton(targetTime: introTargetSeconds) {
            SkipSegmentButton(title: "Skip Intro", systemImage: "goforward") {
                playerManager.userInteracted()
                playerManager.seek(to: introTargetSeconds)
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
        guard duration >= SkipSegmentHeuristics.minimumEpisodeDurationSeconds else {
            return nil
        }

        let inferredTarget = duration.isFinite && duration > 0
            ? min(max(duration * 0.02, 45), 95)
            : SkipSegmentHeuristics.fallbackIntroTargetSeconds

        let upperBound = max(
            duration - SkipSegmentHeuristics.minimumRemainingDurationSeconds,
            SkipSegmentHeuristics.fallbackIntroTargetSeconds
        )
        return min(inferredTarget, upperBound)
    }

    private var resolvedDuration: Double {
        let duration = playerManager.duration
        if duration.isFinite && duration > 0 {
            return duration
        }

        return SkipSegmentHeuristics.fallbackIntroTargetSeconds
            + SkipSegmentHeuristics.minimumRemainingDurationSeconds
            + 1
    }

    private func shouldShowButton(targetTime: Double) -> Bool {
        let currentTime = max(playerManager.currentTime, 0)
        return currentTime < max(targetTime - 1, 1)
    }
}

struct SkipOutroButtonView: View {
    @ObservedObject var playerManager: PlayerManager

    init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
    }

    var body: some View {
        if let outroStartSeconds,
           shouldShowButton(startTime: outroStartSeconds) {
            SkipSegmentButton(title: "Skip Outro", systemImage: "goforward") {
                playerManager.userInteracted()
                if playerManager.canPlayNextItem {
                    playerManager.playNext()
                    return
                }

                playerManager.seek(to: skipTargetTime)
            }
            .accessibilityLabel("Skip Outro")
            .accessibilityHint("Skips the ending section of this episode")
            .accessibilityIdentifier("player.skipOutro")
        }
    }

    private var outroStartSeconds: Double? {
        guard playerManager.contentType == .episode else {
            return nil
        }

        let duration = resolvedDuration
        guard duration >= SkipSegmentHeuristics.minimumEpisodeDurationSeconds else {
            return nil
        }

        let inferredLead = duration.isFinite && duration > 0
            ? min(max(duration * 0.05, 30), 75)
            : SkipSegmentHeuristics.fallbackOutroLeadSeconds

        return max(duration - inferredLead, 0)
    }

    private var resolvedDuration: Double {
        let duration = playerManager.duration
        if duration.isFinite && duration > 0 {
            return duration
        }

        return SkipSegmentHeuristics.minimumEpisodeDurationSeconds
    }

    private var skipTargetTime: Double {
        let duration = resolvedDuration
        let currentTime = max(playerManager.currentTime, 0)
        return min(max(duration - 0.5, currentTime), duration)
    }

    private func shouldShowButton(startTime: Double) -> Bool {
        let currentTime = max(playerManager.currentTime, 0)
        let hideThreshold = max(
            resolvedDuration - SkipSegmentHeuristics.minimumOutroRemainingSeconds,
            startTime
        )
        return currentTime >= startTime && currentTime < hideThreshold
    }
}

private struct SkipSegmentButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(buttonBackground)
            .overlay(buttonStroke)
        }
        .buttonStyle(.plain)
        .desktopHoverLift(enabled: true, scale: 1.02)
    }

    private var buttonBackground: some View {
        Capsule(style: .continuous)
            .fill(Color.black.opacity(0.52))
    }

    private var buttonStroke: some View {
        Capsule(style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.24),
                        Color.white.opacity(0.12),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: 1
            )
    }
}
