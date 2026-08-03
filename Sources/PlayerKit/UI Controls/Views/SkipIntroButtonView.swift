import SwiftUI

private enum SkipSegmentHeuristics {
    static let fallbackIntroTargetSeconds = 85.0
    static let fallbackOutroLeadSeconds = 55.0
    static let minimumEpisodeDurationSeconds = 8 * 60.0
    static let minimumRemainingDurationSeconds = 2 * 60.0
    static let minimumOutroRemainingSeconds = 4.0
}

enum ExactSkipSegmentState: Equatable {
    case absent
    case inactive
    case active(PlayerSkipSegment)

    static func resolve(
        kind: PlayerSkipSegment.Kind,
        segments: [PlayerSkipSegment],
        currentTime: Double
    ) -> Self {
        let matchingSegments = segments.filter { $0.kind == kind }
        guard !matchingSegments.isEmpty else { return .absent }
        guard let activeSegment = matchingSegments.first(where: { $0.contains(currentTime) }) else {
            return .inactive
        }
        return .active(activeSegment)
    }
}

@MainActor
struct SkipIntroButtonView: View {
    @ObservedObject var playerManager: PlayerManager

    init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
    }

    var body: some View {
        if (playerManager.playerItem?.timelineMode ?? .automatic).allowsMarkerSkipActions,
           let introTargetSeconds,
           shouldShowButton(targetTime: introTargetSeconds) {
            SkipSegmentButton(title: title, systemImage: "goforward") {
                playerManager.userInteracted()
                playerManager.seek(to: introTargetSeconds)
            }
            .accessibilityLabel(title)
            .accessibilityHint(playerManager.strings.skipIntroHint)
            .accessibilityIdentifier("player.skipIntro")
        }
    }

    private var title: String {
        playerManager.heuristicSkipButtonTitles.skipIntro
    }

    private var introTargetSeconds: Double? {
        switch exactIntroState {
        case let .active(segment):
            return segment.targetTime
        case .inactive:
            return nil
        case .absent:
            break
        }

        guard !playerManager.suppressesHeuristicSkipButtons else {
            return nil
        }
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

    private var exactIntroState: ExactSkipSegmentState {
        ExactSkipSegmentState.resolve(
            kind: .intro,
            segments: playerManager.playerItem?.skipSegments ?? [],
            currentTime: playerManager.currentTime
        )
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

@MainActor
struct SkipOutroButtonView: View {
    @ObservedObject var playerManager: PlayerManager

    init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
    }

    var body: some View {
        if (playerManager.playerItem?.timelineMode ?? .automatic).allowsMarkerSkipActions,
           let outroStartSeconds,
           shouldShowButton(startTime: outroStartSeconds) {
            SkipSegmentButton(title: title, systemImage: "goforward") {
                playerManager.userInteracted()
                if playerManager.canPlayNextItem {
                    playerManager.playNext()
                    return
                }

                playerManager.seek(to: skipTargetTime)
            }
            .accessibilityLabel(title)
            .accessibilityHint(playerManager.strings.skipOutroHint)
            .accessibilityIdentifier("player.skipOutro")
        }
    }

    // The tap advances instead of seeking when another item is queued, so the label
    // has to follow the same branch or it promises the wrong thing.
    private var title: String {
        let titles = playerManager.heuristicSkipButtonTitles
        return playerManager.canPlayNextItem ? titles.nextEpisode : titles.skipOutro
    }

    private var outroStartSeconds: Double? {
        switch exactOutroState {
        case let .active(segment):
            return segment.startTime
        case .inactive:
            return nil
        case .absent:
            break
        }

        guard !playerManager.suppressesHeuristicSkipButtons else {
            return nil
        }
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

    private var exactOutroState: ExactSkipSegmentState {
        ExactSkipSegmentState.resolve(
            kind: .credits,
            segments: playerManager.playerItem?.skipSegments ?? [],
            currentTime: playerManager.currentTime
        )
    }

    private var resolvedDuration: Double {
        let duration = playerManager.duration
        if duration.isFinite && duration > 0 {
            return duration
        }

        return SkipSegmentHeuristics.minimumEpisodeDurationSeconds
    }

    private var skipTargetTime: Double {
        if case let .active(segment) = exactOutroState {
            return segment.targetTime
        }

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
    @Environment(\.sizeCategory) private var sizeCategory
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))

                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(sizeCategory.isAccessibilityCategory ? 2 : 1)
                    .multilineTextAlignment(.center)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
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
