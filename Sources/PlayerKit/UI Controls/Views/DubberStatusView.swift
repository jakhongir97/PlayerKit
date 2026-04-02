import SwiftUI

struct DubberStatusView: View {
    @ObservedObject var playerManager: PlayerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DubberHeroView(
                phase: visualState,
                accentColor: statusColor,
                title: statusTitle,
                badgeText: statusValueText,
                statusText: compactLiveStatusText,
                headline: statusHeadline,
                subheadline: statusSubheadline
            )

            metricsSection

            if shouldShowProgressSection {
                progressSection
            }

            if let notice = noticeMessage {
                noticeSection(message: notice, isError: playerManager.hasDubberIssue)
            }

            if !visibleActivityEntries.isEmpty {
                activitySection
            }

            actionSection
        }
        .frame(maxWidth: 312, alignment: .leading)
        .glassBackgroundCompat(cornerRadius: 24)
        .accessibilityElement(children: .contain)
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                metricChip(
                    outputLanguageLabel,
                    systemName: "globe",
                    tint: .white,
                    fill: Color.white.opacity(0.10)
                )

                if let statusSummaryText {
                    metricChip(
                        statusSummaryText,
                        systemName: statusSummaryIconName,
                        tint: .white,
                        fill: statusColor.opacity(0.18)
                    )
                }

                if shouldShowETAChip, let eta = playerManager.dubEstimatedRemainingLabel {
                    metricChip(
                        "ETA \(eta)",
                        systemName: "timer",
                        tint: .white.opacity(0.92),
                        fill: Color.white.opacity(0.08)
                    )
                }
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Dub progress")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.62))

                Spacer(minLength: 8)

                if playerManager.dubTotalSegments > 0 {
                    Text("\(playerManager.dubSegmentsReady)/\(playerManager.dubTotalSegments)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .monospacedDigitsCompat()
                } else {
                    Text(playerManager.isDubbedPlaybackActive ? "Live" : "Working")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }
            }

            progressIndicator

            Text(progressFootnote)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.74))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var progressIndicator: some View {
        Group {
            if playerManager.dubTotalSegments > 0 {
                ProgressView(
                    value: Double(playerManager.dubSegmentsReady),
                    total: Double(max(playerManager.dubTotalSegments, 1))
                )
            } else if playerManager.isDubbedPlaybackActive {
                ProgressView(value: 1, total: 1)
            } else {
                ProgressView()
            }
        }
        .scaleEffect(x: 1, y: 0.92, anchor: .center)
        .compatTint(statusColor)
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent activity")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.58))

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleActivityEntries.enumerated()), id: \.element.id) { index, entry in
                    activityRow(entry)

                    if index < visibleActivityEntries.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 1)
                            .padding(.leading, 22)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if playerManager.canStartDubbedPlayback {
                    compactActionButton(
                        title: playerManager.hasDubberIssue ? "Retry Dub" : "Start Dub",
                        systemName: playerManager.hasDubberIssue ? "arrow.clockwise" : "waveform.badge.mic",
                        fill: LinearGradient(
                            colors: primaryActionColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    ) {
                        playerManager.userInteracted()
                        playerManager.pinDubberSheet()
                        if let preferredLanguageCode {
                            playerManager.setDubLanguage(code: preferredLanguageCode)
                        }
                        Task {
                            await playerManager.startDubbedPlayback()
                        }
                    }
                }

                if playerManager.dubSessionID != nil {
                    compactActionButton(
                        title: playerManager.isDubbedPlaybackActive ? "Original Audio" : "Stop Dub",
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

            if playerManager.dubSessionID != nil {
                Label(stopGuidanceText, systemImage: "hand.raised.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.70))
            }
        }
    }

    private func noticeSection(message: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isError ? "exclamationmark.octagon.fill" : "info.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isError ? Color.red.opacity(0.9) : .white.opacity(0.72))

            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.80))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
    }

    private func metricChip(
        _ title: String,
        systemName: String,
        tint: Color,
        fill: Color
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))

            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(tint)
        .padding(.vertical, 5)
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
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
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

    private func activityRow(_ entry: DubberActivityLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconName(for: entry.level))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color(for: entry.level))
                .frame(width: 14, alignment: .center)

            Text(entry.message)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shouldShowProgressSection: Bool {
        playerManager.isDubLoading || playerManager.isDubbedPlaybackActive || playerManager.dubTotalSegments > 0
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

    private var progressFootnote: String {
        if playerManager.hasDubberIssue {
            return "The original track stays on until you retry."
        }
        if visualState == .settling {
            return "Dub is ready. PlayerKit is finalizing the switch."
        }
        if playerManager.isDubbedPlaybackActive {
            return "Switched to dubbed HLS. Stop any time to return to original audio."
        }
        return "Original audio stays on until dubbed HLS is safe to switch."
    }

    private var statusTitle: String {
        "Dubbing.uz"
    }

    private var statusHeadline: String {
        if visualState == .error {
            return "Dubber needs attention"
        }
        if visualState == .live {
            return "Dubbed audio is live"
        }
        if visualState == .settling {
            return "Finishing the handoff"
        }
        if visualState == .loading {
            return playerManager.dubSessionID == nil ? "Starting dubbing" : "Preparing dubbed audio"
        }
        return "Launch an instant dub"
    }

    private var statusSubheadline: String {
        if visualState == .error {
            return "Retry the session or stay on the original audio."
        }
        if visualState == .live {
            return "The translated voice track is active. Return to original audio any time."
        }
        if visualState == .settling {
            return "The translated voice is ready. PlayerKit is attaching the dubbed stream."
        }
        if visualState == .loading {
            return "Original audio stays on while the dubbed HLS stream prepares."
        }
        return "Start dubbing whenever you want a translated voice track."
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

    private var statusSummaryText: String? {
        if playerManager.dubTotalSegments > 0 {
            return "\(playerManager.dubSegmentsReady)/\(playerManager.dubTotalSegments) ready"
        }
        if visualState == .idle {
            return nil
        }
        if visualState == .error {
            return "Needs retry"
        }
        if visualState == .live {
            return "Dub live"
        }
        if visualState == .settling {
            return "Settling"
        }
        return "Auto switch"
    }

    private var statusSummaryIconName: String {
        if playerManager.dubTotalSegments > 0 {
            return "square.stack.3d.up.fill"
        }
        if visualState == .error {
            return "arrow.clockwise"
        }
        if visualState == .live {
            return "waveform.badge.checkmark"
        }
        if visualState == .settling {
            return "arrow.left.arrow.right.circle.fill"
        }
        return "arrow.triangle.2.circlepath"
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
        if visualState == .error {
            return nil
        }

        if visualState == .live {
            return "Dub live"
        }

        if visualState == .settling {
            return "Finalizing switch"
        }

        if visualState == .loading {
            let rawStatus = playerManager.dubProgressMessage?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? playerManager.dubStatus?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Preparing"

            return compactStatusText(from: rawStatus)
        }

        return "Original stays on"
    }

    private var stopGuidanceText: String {
        if playerManager.isDubbedPlaybackActive {
            return "Return to the source track any time."
        }
        return "Stop the dub while the new HLS track prepares."
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

    private func color(for level: DubberActivityLogEntry.Level) -> Color {
        switch level {
        case .info:
            return Color(red: 0.47, green: 0.82, blue: 1.0)
        case .success:
            return Color(red: 0.31, green: 0.92, blue: 0.67)
        case .warning:
            return Color(red: 0.99, green: 0.73, blue: 0.33)
        case .error:
            return Color(red: 0.99, green: 0.42, blue: 0.42)
        }
    }

    private func iconName(for level: DubberActivityLogEntry.Level) -> String {
        switch level {
        case .info:
            return "sparkles"
        case .success:
            return "checkmark.seal.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    private var visualState: DubberVisualState {
        playerManager.dubberVisualState
    }

    private var visibleActivityEntries: [DubberActivityLogEntry] {
        var seenSignatures = Set<String>()
        var entries: [DubberActivityLogEntry] = []

        for entry in playerManager.dubActivityLog {
            let signature = normalizedActivitySignature(for: entry.message)
            guard seenSignatures.insert(signature).inserted else { continue }

            entries.append(entry)

            if entries.count == 2 {
                break
            }
        }

        return entries
    }

    private var shouldShowETAChip: Bool {
        visualState == .loading || visualState == .settling
    }

    private func normalizedActivitySignature(for message: String) -> String {
        String(message.lowercased().map { $0.isNumber ? "#" : $0 })
    }

    private var preferredUzbekOption: DubberLanguageOption? {
        playerManager.availableDubLanguages.first(where: { $0.code.lowercased() == "uz" })
    }

    private var preferredLanguageCode: String? {
        preferredUzbekOption?.code
    }

    private var outputLanguageLabel: String {
        preferredUzbekOption?.name ?? playerManager.selectedDubLanguage?.name ?? "Uzbek"
    }
}
