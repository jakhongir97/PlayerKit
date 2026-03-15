import SwiftUI

struct DubberStatusView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerSection

            if let statusText = compactLiveStatusText {
                liveStatusSection(text: statusText)
            }

            if playerManager.isDubberEnabled {
                languageSection
            }

            if playerManager.dubTotalSegments > 0 {
                progressSection
            }

            if let notice = noticeMessage {
                noticeSection(message: notice, isError: playerManager.hasDubberIssue)
            }

            actionSection
        }
        .frame(maxWidth: 264, alignment: .leading)
        .glassBackgroundCompat(cornerRadius: 18)
        .accessibilityElement(children: .contain)
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: statusIconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(statusColor.opacity(0.20))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(statusTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    compactBadge(
                        statusValueText,
                        tint: .white,
                        fill: statusColor.opacity(0.22)
                    )

                    if playerManager.dubSessionID != nil {
                        compactBadge(
                            playerManager.isDubbedPlaybackActive ? "Dub" : "Orig",
                            tint: .white.opacity(0.92),
                            fill: Color.white.opacity(0.08)
                        )
                    }

                    if playerManager.dubTotalSegments > 0 {
                        compactBadge(
                            "\(playerManager.dubSegmentsReady)/\(playerManager.dubTotalSegments)",
                            tint: .white.opacity(0.92),
                            fill: Color.white.opacity(0.08)
                        )
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var languageSection: some View {
        HStack(spacing: 8) {
            DubberLanguageField(
                title: "To",
                selection: playerManager.selectedDubLanguage,
                options: playerManager.availableDubLanguages
            ) { code in
                playerManager.setDubLanguage(code: code)
            }

            DubberLanguageField(
                title: "From",
                selection: playerManager.selectedDubSourceLanguage,
                options: playerManager.availableDubSourceLanguages
            ) { code in
                playerManager.setDubSourceLanguage(code: code)
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Progress")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.62))

                Spacer(minLength: 8)

                Text("\(playerManager.dubSegmentsReady)/\(playerManager.dubTotalSegments)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .monospacedDigitsCompat()
            }

            ProgressView(
                value: Double(playerManager.dubSegmentsReady),
                total: Double(max(playerManager.dubTotalSegments, 1))
            )
            .scaleEffect(x: 1, y: 0.86, anchor: .center)
            .compatTint(statusColor)
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        HStack(spacing: 8) {
            if playerManager.canStartDubbedPlayback {
                compactActionButton(
                    title: playerManager.hasDubberIssue ? "Retry" : "Start",
                    systemName: playerManager.hasDubberIssue ? "arrow.clockwise" : "waveform.badge.mic",
                    fill: LinearGradient(
                        colors: primaryActionColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                ) {
                    playerManager.userInteracted()
                    Task {
                        await playerManager.startDubbedPlayback()
                    }
                }
            }

            if playerManager.dubSessionID != nil {
                compactActionButton(
                    title: playerManager.isDubbedPlaybackActive ? "Original" : "Stop",
                    systemName: playerManager.isDubbedPlaybackActive ? "speaker.wave.2.fill" : "stop.fill",
                    fill: LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                ) {
                    playerManager.stopDubbingAndReturnToOriginalAudio()
                }
            }
        }
    }

    private func noticeSection(message: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: isError ? "exclamationmark.octagon.fill" : "info.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isError ? Color.red.opacity(0.9) : .white.opacity(0.72))

            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.80))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func liveStatusSection(text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: liveStatusIconName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)

            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .monospacedDigitsCompat()
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(
            Capsule(style: .continuous)
                .fill(liveStatusColor.opacity(0.90))
        )
    }

    private func compactBadge(_ title: String, tint: Color, fill: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(tint)
            .lineLimit(1)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(fill)
            )
    }

    private func compactActionButton(
        title: String,
        systemName: String,
        fill: LinearGradient,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .semibold))

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .background(fill)
            .clipShape(Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .desktopHoverLift()
    }

    private var primaryActionColors: [Color] {
        if playerManager.hasDubberIssue {
            return [
                Color(red: 0.89, green: 0.32, blue: 0.39),
                Color(red: 0.99, green: 0.58, blue: 0.35),
            ]
        }

        return [
            Color(red: 0.16, green: 0.68, blue: 0.92),
            Color(red: 0.22, green: 0.92, blue: 0.72),
        ]
    }

    private var statusTitle: String {
        "Dubbing.uz"
    }

    private var statusValueText: String {
        if playerManager.hasDubberIssue {
            return "Error"
        }
        if playerManager.isDubbedPlaybackActive {
            return "Live"
        }
        if playerManager.isDubLoading {
            return "Running"
        }
        return "Idle"
    }

    private var statusIconName: String {
        if playerManager.hasDubberIssue {
            return "exclamationmark.triangle.fill"
        }
        if playerManager.isDubbedPlaybackActive {
            return "waveform.badge.checkmark"
        }
        if playerManager.isDubLoading {
            return "waveform.badge.mic"
        }
        return "waveform"
    }

    private var statusColor: Color {
        if playerManager.hasDubberIssue {
            return .red
        }
        if playerManager.isDubbedPlaybackActive {
            return .green
        }
        if playerManager.isDubLoading {
            return Color(red: 0.0, green: 0.78, blue: 1.0)
        }
        return .white
    }

    private var noticeMessage: String? {
        if playerManager.hasDubberIssue {
            return playerManager.lastError?.localizedDescription
        }
        return playerManager.dubWarningMessage
    }

    private var compactLiveStatusText: String? {
        if playerManager.hasDubberIssue {
            return nil
        }

        if playerManager.isDubbedPlaybackActive {
            return "Dub live"
        }

        if playerManager.isDubLoading {
            let rawStatus = playerManager.dubProgressMessage?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? playerManager.dubStatus?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Preparing"

            return compactStatusText(from: rawStatus)
        }

        return nil
    }

    private func compactStatusText(from rawStatus: String) -> String {
        let lowercased = rawStatus.lowercased()

        if lowercased.contains("fetching subtitles") {
            return "Fetching subs"
        }
        if lowercased.contains("translating") {
            return "Translating"
        }
        if lowercased.contains("preparing") || lowercased.contains("starting") {
            return "Preparing"
        }
        if lowercased.contains("complete") || lowercased.contains("completed") || lowercased.contains("ready") {
            return "Ready"
        }

        return rawStatus
    }

    private var liveStatusIconName: String {
        if playerManager.isDubbedPlaybackActive {
            return "waveform.badge.checkmark"
        }
        return "waveform.badge.mic"
    }

    private var liveStatusColor: Color {
        playerManager.isDubbedPlaybackActive ? .green : .blue
    }
}

private struct DubberLanguageField: View {
    let title: String
    let selection: DubberLanguageOption?
    let options: [DubberLanguageOption]
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button(option.name) {
                    onSelect(option.code)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.52))

                HStack(spacing: 6) {
                    Text(selection?.name ?? "Select")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.64))
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}
