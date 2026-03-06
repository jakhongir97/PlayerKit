import SwiftUI
import Combine

struct DubberStatusView: View {
    @ObservedObject var playerManager: PlayerManager

    private var presentation: DubberPresentation {
        DubberPresentation(playerManager: playerManager)
    }

    private var logEntries: [DubberActivityLogEntry] {
        Array(playerManager.dubActivityLog.prefix(PlayerKitPlatform.isPhone ? 3 : 4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                DubberPulseBadge(
                    systemImage: presentation.systemImage,
                    primaryColor: presentation.primaryColor,
                    secondaryColor: presentation.secondaryColor,
                    isAnimating: presentation.isAnimating
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(presentation.title)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)

                        statusBadge
                    }

                    Text(presentation.subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.82))
                        .lineLimit(3)
                }

                Spacer(minLength: 12)

                if let callToActionLabel = presentation.callToActionLabel {
                    DubberButton(
                        playerManager: playerManager,
                        title: callToActionLabel
                    )
                }
            }

            stepRow

            if presentation.showsLanguageSelectors {
                languageSelectionSection
            }

            if presentation.showsProgress {
                progressSection
            }

            if let secondaryAction = presentation.secondaryAction {
                actionRow(action: secondaryAction)
            }

            if let noticeMessage = presentation.noticeMessage {
                noticeRow(message: noticeMessage, isError: presentation.mode == .failed)
            }

            if !logEntries.isEmpty && presentation.showsLogs {
                activitySection
            }
        }
        .glassBackgroundCompat(cornerRadius: 24)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(borderGradient, lineWidth: 1)
        )
        .shadow(color: presentation.primaryColor.opacity(0.22), radius: 18, x: 0, y: 10)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: presentation.mode)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: playerManager.dubSegmentsReady)
        .accessibilityElement(children: .contain)
    }

    private var statusBadge: some View {
        Text(presentation.badgeText)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                presentation.primaryColor.opacity(0.95),
                                presentation.secondaryColor.opacity(0.9),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    private var stepRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(presentation.steps.enumerated()), id: \.offset) { index, step in
                DubberStepPill(
                    title: step.title,
                    systemImage: step.systemImage,
                    isCurrent: index == presentation.currentStepIndex,
                    isComplete: index < presentation.currentStepIndex,
                    accentColor: presentation.primaryColor
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var languageSelectionSection: some View {
        HStack(spacing: 10) {
            DubberLanguageMenu(
                title: "To",
                systemImage: "arrow.down.circle.fill",
                selection: playerManager.selectedDubLanguage,
                options: playerManager.availableDubLanguages,
                accentColor: presentation.primaryColor
            ) { code in
                playerManager.setDubLanguage(code: code)
            }

            DubberLanguageMenu(
                title: "From",
                systemImage: "arrow.up.circle.fill",
                selection: playerManager.selectedDubSourceLanguage,
                options: playerManager.availableDubSourceLanguages,
                accentColor: presentation.secondaryColor
            ) { code in
                playerManager.setDubSourceLanguage(code: code)
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Dub Progress")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.76))

                Spacer(minLength: 8)

                Text(presentation.progressValueText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigitsCompat()

                if let etaLabel = presentation.etaLabel {
                    Text(etaLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.1))
                        )
                }
            }

            DubberProgressBar(
                fraction: presentation.progressFraction,
                primaryColor: presentation.primaryColor,
                secondaryColor: presentation.secondaryColor,
                isAnimating: presentation.isAnimating
            )

            Text(presentation.progressCaption)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.78))
                .lineLimit(2)
        }
    }

    private func actionRow(action: DubberInlineAction) -> some View {
        HStack {
            Spacer()

            DubberInlineActionButton(
                title: action.title,
                systemImage: action.systemImage,
                primaryColor: action.primaryColor,
                secondaryColor: action.secondaryColor
            ) {
                switch action.kind {
                case .stopDubbing, .originalAudio:
                    playerManager.stopDubbingAndReturnToOriginalAudio()
                }
            }
        }
    }

    private func noticeRow(message: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isError ? Color(red: 0.98, green: 0.45, blue: 0.38) : Color(red: 0.99, green: 0.79, blue: 0.36))

            Text(message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live Activity")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.76))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(logEntries) { entry in
                    DubberLogRow(entry: entry)
                }
            }
        }
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                presentation.primaryColor.opacity(0.9),
                .white.opacity(0.18),
                presentation.secondaryColor.opacity(0.72),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct DubberCompactStatusView: View {
    @ObservedObject var playerManager: PlayerManager

    private var presentation: DubberPresentation {
        DubberPresentation(playerManager: playerManager)
    }

    var body: some View {
        Button {
            playerManager.userInteracted()
        } label: {
            HStack(spacing: 10) {
                DubberPulseBadge(
                    systemImage: presentation.systemImage,
                    primaryColor: presentation.primaryColor,
                    secondaryColor: presentation.secondaryColor,
                    isAnimating: presentation.isAnimating,
                    size: 40,
                    iconSize: 16
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.compactLabel)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    if let etaLabel = presentation.etaLabel {
                        Text(etaLabel)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.78))
                    } else if presentation.showsProgress {
                        DubberProgressBar(
                            fraction: presentation.progressFraction,
                            primaryColor: presentation.primaryColor,
                            secondaryColor: presentation.secondaryColor,
                            isAnimating: presentation.isAnimating,
                            height: 5
                        )
                        .frame(width: 110)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .modifier(GlassCapsuleBackground())
            .overlay(
                Capsule(style: .continuous)
                    .stroke(borderGradient, lineWidth: 1)
            )
            .shadow(color: presentation.primaryColor.opacity(0.22), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(presentation.compactLabel)
        .accessibilityHint("Shows detailed dubbing controls")
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                presentation.primaryColor.opacity(0.95),
                .white.opacity(0.18),
                presentation.secondaryColor.opacity(0.78),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private struct DubberPulseBadge: View {
    let systemImage: String
    let primaryColor: Color
    let secondaryColor: Color
    let isAnimating: Bool
    var size: CGFloat = 56
    var iconSize: CGFloat = 22

    @State private var animatePulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [primaryColor.opacity(0.92), secondaryColor.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )

            if isAnimating {
                Circle()
                    .stroke(primaryColor.opacity(0.45), lineWidth: 2)
                    .scaleEffect(animatePulse ? 1.55 : 0.92)
                    .opacity(animatePulse ? 0 : 0.72)

                Circle()
                    .stroke(secondaryColor.opacity(0.36), lineWidth: 2)
                    .scaleEffect(animatePulse ? 1.82 : 0.94)
                    .opacity(animatePulse ? 0 : 0.56)
            }

            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(.white)
                .hierarchicalSymbolRendering()
        }
        .frame(width: size, height: size)
        .onAppear {
            animatePulse = false
            guard isAnimating else { return }
            withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                animatePulse = true
            }
        }
        .onReceive(Just(isAnimating).removeDuplicates()) { shouldAnimate in
            guard shouldAnimate else {
                animatePulse = false
                return
            }

            animatePulse = false
            withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                animatePulse = true
            }
        }
    }
}

private struct DubberProgressBar: View {
    let fraction: Double
    let primaryColor: Color
    let secondaryColor: Color
    let isAnimating: Bool
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.12))

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [primaryColor, secondaryColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(proxy.size.width * CGFloat(clampedFraction), isAnimating ? height * 2.2 : 0))
                    .shadow(color: primaryColor.opacity(0.28), radius: 8, x: 0, y: 4)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private var clampedFraction: Double {
        min(max(fraction, 0), 1)
    }
}

private struct DubberLanguageMenu: View {
    let title: String
    let systemImage: String
    let selection: DubberLanguageOption?
    let options: [DubberLanguageOption]
    let accentColor: Color
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    onSelect(option.code)
                } label: {
                    HStack {
                        Text(option.name)

                        if option.code == selection?.code {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))

                    Text(selection?.name ?? "Choose")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.72))
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(accentColor.opacity(0.34), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DubberStepPill: View {
    let title: String
    let systemImage: String
    let isCurrent: Bool
    let isComplete: Bool
    let accentColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(iconColor)

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(isCurrent || isComplete ? 0.96 : 0.72))
                .lineLimit(1)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var iconColor: Color {
        if isComplete || isCurrent {
            return .white
        }
        return .white.opacity(0.68)
    }

    private var backgroundColor: Color {
        if isComplete {
            return accentColor.opacity(0.3)
        }

        if isCurrent {
            return accentColor.opacity(0.2)
        }

        return Color.white.opacity(0.06)
    }

    private var borderColor: Color {
        if isComplete || isCurrent {
            return accentColor.opacity(0.48)
        }
        return .white.opacity(0.1)
    }
}

private struct DubberInlineActionButton: View {
    let title: String
    let systemImage: String
    let primaryColor: Color
    let secondaryColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))

                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [primaryColor, secondaryColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DubberLogRow: View {
    let entry: DubberActivityLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(levelColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(timeString(from: entry.timestamp))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                        .monospacedDigitsCompat()

                    Text(entry.level.rawValue.capitalized)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(levelColor)
                }

                Text(entry.message)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var levelColor: Color {
        switch entry.level {
        case .info:
            return Color(red: 0.45, green: 0.78, blue: 0.98)
        case .success:
            return Color(red: 0.34, green: 0.91, blue: 0.65)
        case .warning:
            return Color(red: 0.99, green: 0.79, blue: 0.36)
        case .error:
            return Color(red: 0.98, green: 0.45, blue: 0.38)
        }
    }

    private func timeString(from date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }
}

private struct DubberPresentation {
    enum Mode {
        case idle
        case starting
        case generating
        case reconnecting
        case ready
        case failed
    }

    struct Step {
        let title: String
        let systemImage: String
    }

    let mode: Mode
    let title: String
    let subtitle: String
    let badgeText: String
    let compactLabel: String
    let systemImage: String
    let primaryColor: Color
    let secondaryColor: Color
    let currentStepIndex: Int
    let callToActionLabel: String?
    let secondaryAction: DubberInlineAction?
    let showsLanguageSelectors: Bool
    let showsProgress: Bool
    let progressFraction: Double
    let progressValueText: String
    let progressCaption: String
    let etaLabel: String?
    let noticeMessage: String?
    let showsLogs: Bool
    let isAnimating: Bool
    let steps: [Step] = [
        Step(title: "Hear", systemImage: "waveform"),
        Step(title: "Build Voice", systemImage: "text.alignleft"),
        Step(title: "Play Dub", systemImage: "speaker.wave.2.fill"),
    ]

    init(playerManager: PlayerManager) {
        let dubError = playerManager.hasDubberIssue ? playerManager.lastError?.localizedDescription : nil
        let progressText = playerManager.dubTotalSegments > 0
            ? "\(playerManager.dubSegmentsReady) / \(playerManager.dubTotalSegments)"
            : (playerManager.isDubbedPlaybackActive ? "Ready" : "Waiting")
        let targetLanguageName = playerManager.selectedDubLanguage?.name ?? "Target"
        let sourceLanguageName = playerManager.selectedDubSourceLanguage?.name ?? "Auto Detect"
        let routeLabel = sourceLanguageName == "Auto Detect"
            ? "to \(targetLanguageName)"
            : "\(sourceLanguageName) to \(targetLanguageName)"

        if let dubError {
            mode = .failed
            title = "Dubbing Needs Another Try"
            subtitle = "PlayerKit could not finish the dub right now. Adjust the language pair or retry from here."
            badgeText = "Retry"
            compactLabel = "Dub failed"
            systemImage = "xmark.octagon.fill"
            primaryColor = Color(red: 0.92, green: 0.34, blue: 0.38)
            secondaryColor = Color(red: 0.98, green: 0.55, blue: 0.35)
            currentStepIndex = playerManager.dubSegmentsReady > 0 ? 1 : 0
            callToActionLabel = playerManager.canStartDubbedPlayback ? "Retry Dubbing" : nil
            secondaryAction = nil
            showsLanguageSelectors = true
            showsProgress = playerManager.dubSegmentsReady > 0 || playerManager.dubTotalSegments > 0
            progressFraction = playerManager.dubProgressFraction
            progressValueText = progressText
            progressCaption = playerManager.dubProgressMessage ?? "The last dub session stopped before playback could switch \(routeLabel)."
            etaLabel = nil
            noticeMessage = dubError
            showsLogs = true
            isAnimating = false
            return
        }

        if let warning = playerManager.dubWarningMessage, playerManager.isDubLoading {
            mode = .reconnecting
            title = "Keeping The Dub Alive"
            subtitle = "The connection blinked, so PlayerKit is reconnecting without losing your place."
            badgeText = "Reconnecting"
            compactLabel = "Reconnecting dub"
            systemImage = "arrow.clockwise.circle.fill"
            primaryColor = Color(red: 0.95, green: 0.62, blue: 0.23)
            secondaryColor = Color(red: 0.99, green: 0.82, blue: 0.38)
            currentStepIndex = playerManager.dubSegmentsReady > 0 ? 1 : 0
            callToActionLabel = nil
            secondaryAction = DubberInlineAction(
                kind: .stopDubbing,
                title: "Stop Dubbing",
                systemImage: "stop.fill",
                primaryColor: Color(red: 0.86, green: 0.45, blue: 0.21),
                secondaryColor: Color(red: 0.97, green: 0.69, blue: 0.27)
            )
            showsLanguageSelectors = false
            showsProgress = true
            progressFraction = playerManager.dubProgressFraction
            progressValueText = progressText
            progressCaption = playerManager.dubProgressMessage ?? "Translation keeps going \(routeLabel) while the status stream reconnects."
            etaLabel = playerManager.dubEstimatedRemainingLabel
            noticeMessage = warning
            showsLogs = true
            isAnimating = true
            return
        }

        if playerManager.isDubbedPlaybackActive || (!playerManager.isDubLoading && playerManager.dubSessionID != nil) {
            mode = .ready
            title = "Dubbed Voice Is Live"
            subtitle = playerManager.isDubbedPlaybackActive
                ? "The player has switched to the new voice track."
                : "The dubbed voice is ready for playback."
            badgeText = "Live"
            compactLabel = "Dubbed voice live"
            systemImage = "speaker.wave.2.fill"
            primaryColor = Color(red: 0.18, green: 0.8, blue: 0.55)
            secondaryColor = Color(red: 0.28, green: 0.91, blue: 0.83)
            currentStepIndex = 2
            callToActionLabel = nil
            secondaryAction = DubberInlineAction(
                kind: .originalAudio,
                title: "Original Audio",
                systemImage: "speaker.slash.fill",
                primaryColor: Color(red: 0.33, green: 0.38, blue: 0.48),
                secondaryColor: Color(red: 0.47, green: 0.56, blue: 0.66)
            )
            showsLanguageSelectors = false
            showsProgress = true
            progressFraction = 1
            progressValueText = "Ready"
            progressCaption = "PlayerKit now uses the dubbed stream while keeping your playback position."
            etaLabel = nil
            noticeMessage = nil
            showsLogs = true
            isAnimating = false
            return
        }

        if playerManager.isDubLoading {
            let hasSegmentData = playerManager.dubSegmentsReady > 0 || playerManager.dubTotalSegments > 0
            mode = hasSegmentData ? .generating : .starting
            title = hasSegmentData ? "Building A New Voice" : "Opening The Dubbing Studio"
            subtitle = hasSegmentData
                ? "\(playerManager.dubSegmentsReady) of \(max(playerManager.dubTotalSegments, playerManager.dubSegmentsReady)) voice pieces are ready. PlayerKit will switch only when there is enough safe coverage."
                : "PlayerKit is connecting to Dubber and waiting for the first translated voice pieces."
            badgeText = hasSegmentData ? "Working" : "Connecting"
            compactLabel = hasSegmentData && playerManager.dubTotalSegments > 0
                ? "Dubbing \(playerManager.dubSegmentsReady)/\(playerManager.dubTotalSegments)"
                : "Starting dub"
            systemImage = "waveform.circle.fill"
            primaryColor = Color(red: 0.17, green: 0.69, blue: 0.92)
            secondaryColor = Color(red: 0.22, green: 0.92, blue: 0.72)
            currentStepIndex = hasSegmentData ? 1 : 0
            callToActionLabel = nil
            secondaryAction = DubberInlineAction(
                kind: .stopDubbing,
                title: "Stop Dubbing",
                systemImage: "stop.fill",
                primaryColor: Color(red: 0.86, green: 0.45, blue: 0.21),
                secondaryColor: Color(red: 0.97, green: 0.69, blue: 0.27)
            )
            showsLanguageSelectors = false
            showsProgress = true
            progressFraction = playerManager.dubProgressFraction
            progressValueText = progressText
            progressCaption = playerManager.dubProgressMessage ?? "The original audio keeps playing until Dubber has enough translated segments \(routeLabel)."
            etaLabel = playerManager.dubEstimatedRemainingLabel
            noticeMessage = nil
            showsLogs = true
            isAnimating = true
            return
        }

        mode = .idle
        title = "Dub This Video Into A New Voice"
        subtitle = "One tap starts translation while the original audio keeps playing. PlayerKit switches only when the dub is ready."
        badgeText = "Ready"
        compactLabel = "Start dubbing"
        systemImage = "waveform.circle.fill"
        primaryColor = Color(red: 0.17, green: 0.69, blue: 0.92)
        secondaryColor = Color(red: 0.22, green: 0.92, blue: 0.72)
        currentStepIndex = 0
        callToActionLabel = playerManager.canStartDubbedPlayback ? "Start Dubbing" : nil
        secondaryAction = nil
        showsLanguageSelectors = true
        showsProgress = false
        progressFraction = 0
        progressValueText = "Ready"
        progressCaption = "The new voice track will appear here once Dubber begins translating \(routeLabel)."
        etaLabel = nil
        noticeMessage = nil
        showsLogs = false
        isAnimating = false
    }
}

private struct DubberInlineAction {
    enum Kind {
        case stopDubbing
        case originalAudio
    }

    let kind: Kind
    let title: String
    let systemImage: String
    let primaryColor: Color
    let secondaryColor: Color
}
