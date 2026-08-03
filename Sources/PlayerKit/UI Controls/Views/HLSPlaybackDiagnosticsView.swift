#if os(macOS)
import AppKit
import Combine
import OSLog
import SwiftUI

let playbackDiagnosticsLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.netco.itv",
    category: "PlaybackHealth"
)

enum PlaybackDiagnosticsTheme {
    static let background = Color(red: 20 / 255, green: 22 / 255, blue: 23 / 255)
    static let recessed = Color(red: 15 / 255, green: 18 / 255, blue: 18 / 255)
    static let elevated = Color(red: 27 / 255, green: 28 / 255, blue: 29 / 255)
    static let primary = Color(red: 246 / 255, green: 248 / 255, blue: 251 / 255)
    static let secondary = Color(red: 194 / 255, green: 201 / 255, blue: 214 / 255)
    static let tertiary = Color(red: 143 / 255, green: 153 / 255, blue: 171 / 255)
    static let green = Color(red: 72 / 255, green: 240 / 255, blue: 0)
    static let live = Color(red: 1, green: 69 / 255, blue: 77 / 255)
    static let warning = Color.orange
    static let danger = Color.pink
    static let divider = Color.white.opacity(0.10)

    static func color(for level: PlaybackDiagnosticsLevel) -> Color {
        switch level {
        case .observation:
            return tertiary
        case .notice:
            return Color.cyan
        case .warning:
            return warning
        case .critical:
            return danger
        }
    }

    static func label(for level: PlaybackDiagnosticsLevel) -> String {
        switch level {
        case .observation:
            return "INFO"
        case .notice:
            return "NOTICE"
        case .warning:
            return "WARNING"
        case .critical:
            return "CRITICAL"
        }
    }
}

enum PlaybackDiagnosticsFormat {
    static func seconds(_ value: Double?, unavailable: String = "Not measured") -> String {
        guard let value, value.isFinite, value >= 0 else { return unavailable }
        return String(format: "%.2f s", value)
    }

    static func duration(_ value: TimeInterval) -> String {
        if value < 60 {
            return String(format: "%.1f s", value)
        }
        return String(format: "%d:%02d", Int(value) / 60, Int(value) % 60)
    }

    static func bitRate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "Not measured" }
        if value >= 1_000_000 {
            return String(format: "%.2f Mbps", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.0f Kbps", value / 1_000)
        }
        return String(format: "%.0f bps", value)
    }

    static func integer(_ value: Int?) -> String {
        value.map(String.init) ?? "Not measured"
    }

    static func shortTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }

    static func fullTime(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .standard) ?? "Not measured"
    }

    static func yesNo(_ value: Bool?) -> String {
        value.map { $0 ? "Yes" : "No" } ?? "Not measured"
    }
}

enum PlaybackDiagnosticsCurrentStatus: Equatable {
    case noProblemDetected
    case needsAttention(PlaybackDiagnosticsLevel)
    case waiting
    case failed
    case nothingPlaying
    case checkLimited
    case detailsUnavailable

    static func resolve(
        availability: PlaybackDiagnosticsAvailability,
        itemStatus: String,
        timeControlStatus: String,
        highestActiveIssue: PlaybackDiagnosticsLevel?
    ) -> Self {
        if availability == .noPlayerItem {
            return .nothingPlaying
        }
        if availability == .unsupportedBackend {
            return .detailsUnavailable
        }
        if itemStatus == "failed" {
            return .failed
        }
        if let highestActiveIssue, highestActiveIssue >= .warning {
            return .needsAttention(highestActiveIssue)
        }
        if timeControlStatus == "waiting" {
            return .waiting
        }
        if let highestActiveIssue {
            return .needsAttention(highestActiveIssue)
        }
        switch availability {
        case .startingAVMetrics,
             .failedAVMetrics,
             .endedAVMetrics,
             .monitoringDisabled,
             .monitorNotAttached:
            return .checkLimited
        case .activeAVMetrics,
             .activeErrorLogFallback,
             .noPlayerItem,
             .unsupportedBackend:
            break
        }
        return .noProblemDetected
    }

    var title: String {
        switch self {
        case .noProblemDetected:
            return "No problem detected now"
        case let .needsAttention(level):
            return level >= .warning ? "Playback needs attention" : "Session has findings"
        case .waiting:
            return "Playback is waiting"
        case .failed:
            return "Playback failed"
        case .nothingPlaying:
            return "Nothing is playing"
        case .checkLimited:
            return "Monitoring is limited"
        case .detailsUnavailable:
            return "Playback details unavailable"
        }
    }
}

private struct DiagnosticsFeedback: Identifiable {
    let id = UUID()
    let message: String
    let succeeded: Bool
}

@MainActor
public struct HLSPlaybackDiagnosticsView: View {
    @ObservedObject private var playerManager: PlayerManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var snapshot: PlaybackDiagnosticsSnapshot
    @State private var sampledContentTitle: String
    @State private var selectedIncidentID: UUID?
    @State private var isLive = true
    @State private var showsTechnicalEvidence = false
    @State private var zoomSeconds: TimeInterval = 300
    @State private var displayTime = Date()
    @State private var feedback: DiagnosticsFeedback?

    private let keepsPlayerControlsVisible: Bool
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(
        playerManager: PlayerManager,
        keepsPlayerControlsVisible: Bool = true
    ) {
        self.playerManager = playerManager
        self.keepsPlayerControlsVisible = keepsPlayerControlsVisible
        let initialSnapshot = playerManager.fetchPlaybackDiagnostics()
        _snapshot = State(initialValue: initialSnapshot)
        _sampledContentTitle = State(
            initialValue: Self.contentTitle(from: playerManager)
        )
        _selectedIncidentID = State(
            initialValue: initialSnapshot.storyboard.incidents.last?.id
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            kpiRibbon

            HLSPlaybackStoryboardTimelineView(
                storyboard: snapshot.storyboard,
                displayTime: displayTime,
                zoomSeconds: $zoomSeconds,
                selectedIncidentID: $selectedIncidentID
            )
            .frame(minHeight: 230, idealHeight: 310)

            Divider()
                .overlay(PlaybackDiagnosticsTheme.divider)

            lowerWorkspace
                .frame(minHeight: 190)

            statusBar
        }
        .foregroundStyle(PlaybackDiagnosticsTheme.primary)
        .background(PlaybackDiagnosticsTheme.background)
        .frame(
            minWidth: 760,
            idealWidth: 980,
            minHeight: 500,
            idealHeight: 720
        )
        .toolbarRole(.editor)
        .toolbar {
            toolbarContent
        }
        .inspector(isPresented: $showsTechnicalEvidence) {
            HLSPlaybackTechnicalEvidenceView(snapshot: snapshot)
                .inspectorColumnWidth(min: 300, ideal: 360, max: 440)
        }
        .overlay(alignment: .bottom) {
            feedbackOverlay
        }
        .onAppear {
            if keepsPlayerControlsVisible {
                playerManager.userInteracting = true
                playerManager.userInteracted()
            }
            refresh()
        }
        .onDisappear {
            if keepsPlayerControlsVisible {
                playerManager.userInteracting = false
                playerManager.userInteracted()
            }
        }
        .onReceive(timer) { now in
            guard isLive else { return }
            displayTime = now
            refresh()
        }
        .onReceive(playerManager.$playerItem.dropFirst()) { _ in
            // Asset/backend changes intentionally reset a paused presentation so
            // it can never keep showing evidence from the previous session.
            DispatchQueue.main.async {
                displayTime = Date()
                refresh()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Session Storyboard")
                    .font(.system(size: 12, weight: .semibold))
                Text(sampledContentTitle)
                    .font(.system(size: 10))
                    .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: 220, alignment: .leading)
            .accessibilityElement(children: .combine)
        }

        ToolbarItem(placement: .principal) {
            HStack(spacing: 7) {
                Image(systemName: statusIcon)
                Text(currentStatus.title)
                    .font(.system(size: 11, weight: .semibold))
                Text("·")
                    .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
                Text(coverageTitle)
                    .font(.system(size: 10))
                    .foregroundStyle(PlaybackDiagnosticsTheme.secondary)
            }
            .foregroundStyle(statusColor)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(currentStatus.title). Monitoring coverage: \(coverageTitle)"
            )
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: toggleLive) {
                Label(
                    isLive ? "Live" : "Paused",
                    systemImage: isLive ? "record.circle.fill" : "pause.circle"
                )
                .labelStyle(.titleAndIcon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(
                    isLive
                        ? PlaybackDiagnosticsTheme.live
                        : PlaybackDiagnosticsTheme.secondary
                )
            }
            .help(isLive ? "Pause live display updates" : "Resume live display updates")
            .accessibilityIdentifier("player.diagnostics.live")

            Button(action: captureBookmark) {
                Image(systemName: "bookmark.badge.plus")
            }
            .help("Save Moment")
            .accessibilityLabel("Save Moment")
            .accessibilityIdentifier("player.diagnostics.bookmark")
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(!playerManager.hasActivePlaybackDiagnosticsItem)

            Button(action: copyReport) {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy privacy-safe report")
            .accessibilityLabel("Copy Report")
            .accessibilityIdentifier("player.diagnostics.copy")
            .keyboardShortcut("c", modifiers: [.command, .option])

            Button {
                showsTechnicalEvidence.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .help("Technical Evidence")
            .accessibilityLabel(
                showsTechnicalEvidence
                    ? "Hide Technical Evidence"
                    : "Show Technical Evidence"
            )
            .accessibilityIdentifier("player.diagnostics.inspector")
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }

    private var kpiRibbon: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                kpi(
                    "Startup to keep-up",
                    startupValue,
                    accessibilityValue: startupValue
                )
                kpi(
                    "Confirmed rebuffer",
                    confirmedRebufferValue,
                    accessibilityValue: confirmedRebufferValue
                )
                kpi(
                    "Confirmed stalls",
                    confirmedStallValue,
                    accessibilityValue: confirmedStallValue
                )
                kpi(
                    "Buffer now",
                    PlaybackDiagnosticsFormat.seconds(snapshot.playback.bufferHeadroom),
                    accessibilityValue: PlaybackDiagnosticsFormat.seconds(
                        snapshot.playback.bufferHeadroom
                    )
                )
                kpi(
                    "Rendition",
                    renditionValue,
                    accessibilityValue: renditionValue,
                    width: 190
                )
                kpi(
                    "Dropped frames",
                    PlaybackDiagnosticsFormat.integer(
                        snapshot.network.droppedVideoFrameCount
                    ),
                    accessibilityValue: PlaybackDiagnosticsFormat.integer(
                        snapshot.network.droppedVideoFrameCount
                    )
                )
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 54)
        .background(PlaybackDiagnosticsTheme.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PlaybackDiagnosticsTheme.divider)
                .frame(height: 1)
        }
    }

    private func kpi(
        _ title: String,
        _ value: String,
        accessibilityValue: String,
        width: CGFloat = 138
    ) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(.caption2.bold())
                    .tracking(0.6)
                    .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(PlaybackDiagnosticsTheme.primary)
                    .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(accessibilityValue)

            Rectangle()
                .fill(PlaybackDiagnosticsTheme.divider)
                .frame(width: 1, height: 28)
                .padding(.horizontal, 12)
        }
    }

    private var lowerWorkspace: some View {
        HSplitView {
            incidentTable
                .frame(minWidth: 385, idealWidth: 540)

            incidentAnalysis
                .frame(minWidth: 300, idealWidth: 430)
        }
        .background(PlaybackDiagnosticsTheme.background)
    }

    private var incidentTable: some View {
        VStack(spacing: 0) {
            sectionHeader(
                "Automatic Incidents",
                detail: "\(snapshot.storyboard.incidents.count) retained"
            )

            Table(sortedIncidents, selection: $selectedIncidentID) {
                TableColumn("Severity") { incident in
                    Label(
                        PlaybackDiagnosticsTheme.label(for: incident.severity),
                        systemImage: severityIcon(incident.severity)
                    )
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(
                        PlaybackDiagnosticsTheme.color(for: incident.severity)
                    )
                    .accessibilityLabel(
                        "Severity \(PlaybackDiagnosticsTheme.label(for: incident.severity))"
                    )
                }
                .width(min: 78, ideal: 88)

                TableColumn("State") { incident in
                    Text(incident.state == .active ? "Active" : "Recovered")
                        .font(.system(size: 11, weight: .medium))
                }
                .width(min: 58, ideal: 72)

                TableColumn("Start") { incident in
                    Text(PlaybackDiagnosticsFormat.shortTime(incident.startedAt))
                        .font(.system(size: 10, design: .monospaced))
                }
                .width(min: 66, ideal: 76)

                TableColumn("Duration") { incident in
                    Text(
                        PlaybackDiagnosticsFormat.duration(
                            incident.duration(
                                at: snapshot.storyboard.endedAt ?? displayTime
                            )
                        )
                    )
                    .font(.system(size: 10, design: .monospaced))
                }
                .width(min: 54, ideal: 66)

                TableColumn("Likely cause") { incident in
                    Text(incident.kind.title)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .help(incident.likelyCause)
                }
                .width(min: 110, ideal: 190)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            .background(PlaybackDiagnosticsTheme.background)
            .overlay {
                if sortedIncidents.isEmpty {
                    ContentUnavailableView {
                        Label("No automatic incidents", systemImage: "checkmark.circle")
                    } description: {
                        Text(
                            snapshot.playback.itemStatus == "unavailable"
                                ? "Start playback to begin the session storyboard."
                                : "No correlated incident has been detected in retained evidence."
                        )
                    }
                    .foregroundStyle(PlaybackDiagnosticsTheme.secondary)
                }
            }
            .accessibilityIdentifier("player.diagnostics.incident.table")
        }
    }

    private var incidentAnalysis: some View {
        VStack(spacing: 0) {
            sectionHeader("Incident Analysis", detail: selectedIncident?.state.rawValue.capitalized)

            if let incident = selectedIncident {
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        Label(
                            incident.kind.title,
                            systemImage: severityIcon(incident.severity)
                        )
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(
                            PlaybackDiagnosticsTheme.color(for: incident.severity)
                        )

                        analysisSection("Impact", incident.impact)
                        analysisSection("Likely cause", incident.likelyCause)

                        VStack(alignment: .leading, spacing: 6) {
                            analysisLabel("Evidence")
                            Text(incident.evidenceStrength.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                            ForEach(incident.measuredValues, id: \.self) { value in
                                Label(value, systemImage: "waveform.path.ecg")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(PlaybackDiagnosticsTheme.secondary)
                            }
                            ForEach(selectedIncidentEvidence) { evidence in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(PlaybackDiagnosticsFormat.shortTime(evidence.occurredAt))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
                                    Text(evidence.title)
                                        .font(.system(size: 10))
                                    if let measurement = evidence.measurement {
                                        Text("· \(measurement)")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(PlaybackDiagnosticsTheme.secondary)
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Label("Recommended action", systemImage: "arrow.right.circle")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(PlaybackDiagnosticsTheme.green)
                                .textCase(.uppercase)
                            Text(incident.nextAction)
                                .font(.system(size: 11))
                                .foregroundStyle(PlaybackDiagnosticsTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 10)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(PlaybackDiagnosticsTheme.divider)
                                .frame(height: 1)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("player.diagnostics.incident.analysis")
            } else {
                ContentUnavailableView {
                    Label(currentStatus.title, systemImage: statusIcon)
                } description: {
                    Text(statusDetail)
                }
                .foregroundStyle(PlaybackDiagnosticsTheme.secondary)
            }
        }
        .background(PlaybackDiagnosticsTheme.recessed)
    }

    private func sectionHeader(_ title: String, detail: String?) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 31)
        .background(PlaybackDiagnosticsTheme.elevated)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PlaybackDiagnosticsTheme.divider)
                .frame(height: 1)
        }
    }

    private func analysisLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.bold())
            .tracking(0.6)
            .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
    }

    private func analysisSection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            analysisLabel(title)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(PlaybackDiagnosticsTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 9) {
            Label("Retention 300 s circular", systemImage: "clock.arrow.circlepath")
            dividerDot
            Text("\(snapshot.storyboard.samples.count) samples")
            dividerDot
            Label(coverageTitle, systemImage: coverageIcon)
            Spacer()
            Text(
                snapshot.history.isIncomplete
                    ? "Signal history partial"
                    : "Privacy-safe local evidence"
            )
            Image(systemName: "hand.raised.fill")
        }
        .font(.caption2)
        .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
        .padding(.horizontal, 11)
        .frame(height: 24)
        .background(PlaybackDiagnosticsTheme.elevated)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PlaybackDiagnosticsTheme.divider)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var dividerDot: some View {
        Circle()
            .fill(PlaybackDiagnosticsTheme.divider)
            .frame(width: 3, height: 3)
    }

    @ViewBuilder
    private var feedbackOverlay: some View {
        if let feedback {
            Label(
                feedback.message,
                systemImage: feedback.succeeded
                    ? "checkmark.circle.fill"
                    : "xmark.circle.fill"
            )
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(
                feedback.succeeded
                    ? PlaybackDiagnosticsTheme.green
                    : PlaybackDiagnosticsTheme.danger
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 28)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            .allowsHitTesting(false)
            .accessibilityIdentifier("player.diagnostics.feedback")
        }
    }

    private var sortedIncidents: [PlaybackDiagnosticsAutomaticIncident] {
        snapshot.storyboard.incidents.sorted { lhs, rhs in
            if lhs.state != rhs.state {
                return lhs.state == .active
            }
            return lhs.startedAt > rhs.startedAt
        }
    }

    private var selectedIncident: PlaybackDiagnosticsAutomaticIncident? {
        guard let selectedIncidentID else { return nil }
        return snapshot.storyboard.incidents.first { $0.id == selectedIncidentID }
    }

    private var selectedIncidentEvidence: [PlaybackDiagnosticsEvidence] {
        guard let selectedIncident else { return [] }
        let ids = Set(selectedIncident.evidenceIDs)
        return snapshot.storyboard.evidence
            .filter { ids.contains($0.id) }
            .sorted { $0.occurredAt < $1.occurredAt }
    }

    private var currentStatus: PlaybackDiagnosticsCurrentStatus {
        let automaticLevel = snapshot.storyboard.incidents
            .filter { $0.state == .active }
            .map(\.severity)
            .max()
        let issueLevel = snapshot.issues()
            .filter { $0.scope == .active }
            .map(\.level)
            .max()
        return PlaybackDiagnosticsCurrentStatus.resolve(
            availability: snapshot.session.availability,
            itemStatus: snapshot.playback.itemStatus,
            timeControlStatus: snapshot.playback.timeControlStatus,
            highestActiveIssue: [automaticLevel, issueLevel].compactMap { $0 }.max()
        )
    }

    private var statusColor: Color {
        switch currentStatus {
        case .noProblemDetected:
            return PlaybackDiagnosticsTheme.green
        case .needsAttention(.critical), .failed:
            return PlaybackDiagnosticsTheme.danger
        case .needsAttention(.warning), .waiting:
            return PlaybackDiagnosticsTheme.warning
        case .needsAttention, .checkLimited:
            return Color.cyan
        case .nothingPlaying, .detailsUnavailable:
            return PlaybackDiagnosticsTheme.tertiary
        }
    }

    private var statusIcon: String {
        switch currentStatus {
        case .noProblemDetected:
            return "checkmark.circle.fill"
        case .needsAttention(.critical), .failed:
            return "xmark.octagon.fill"
        case .needsAttention(.warning), .waiting:
            return "exclamationmark.triangle.fill"
        case .needsAttention:
            return "info.circle.fill"
        case .nothingPlaying:
            return "play.slash"
        case .checkLimited:
            return "eye.trianglebadge.exclamationmark"
        case .detailsUnavailable:
            return "questionmark.circle"
        }
    }

    private var statusDetail: String {
        switch currentStatus {
        case .noProblemDetected:
            return "No active incident is supported by retained measured evidence."
        case .waiting:
            return "Playback is currently waiting. Initial and seek waits are not classified as rebuffers."
        case .checkLimited:
            return coverageTitle
        case .nothingPlaying:
            return "Start AVPlayer playback to collect session evidence."
        case .detailsUnavailable:
            return "The current playback backend does not expose this monitor."
        case .failed:
            return "AVFoundation reports that the current item failed."
        case .needsAttention:
            return "Select an automatic incident to inspect measured evidence."
        }
    }

    private var coverageTitle: String {
        switch snapshot.session.availability {
        case .activeAVMetrics:
            return "AVMetrics + player state · 1 Hz"
        case .activeErrorLogFallback:
            return "Fallback player/error evidence · 1 Hz"
        default:
            return snapshot.session.availability.title
        }
    }

    private var coverageIcon: String {
        switch snapshot.session.availability {
        case .activeAVMetrics:
            return "scope"
        case .activeErrorLogFallback:
            return "eye"
        default:
            return "eye.trianglebadge.exclamationmark"
        }
    }

    private var startupValue: String {
        PlaybackDiagnosticsFormat.seconds(
            snapshot.monitor?.likelyToKeepUp.initial?.timeTaken
                ?? sessionInterval(
                    to: snapshot.storyboard.firstLikelyToKeepUpAt
                )
        )
    }

    private func sessionInterval(to end: Date?) -> TimeInterval? {
        guard let start = snapshot.storyboard.sessionStartedAt
                ?? snapshot.session.startedAt,
              let end else {
            return nil
        }
        let value = end.timeIntervalSince(start)
        return value.isFinite && value >= 0 ? value : nil
    }

    private var confirmedRebufferValue: String {
        guard snapshot.session.monitorAttached else { return "Not measured" }
        let total = snapshot.storyboard.incidents
            .filter { $0.kind == .confirmedRebuffer }
            .map {
                $0.duration(at: snapshot.storyboard.endedAt ?? displayTime)
            }
            .reduce(0, +)
        return PlaybackDiagnosticsFormat.seconds(total)
    }

    private var confirmedStallValue: String {
        if let monitor = snapshot.monitor {
            return String(monitor.stallCount)
        }
        return PlaybackDiagnosticsFormat.integer(snapshot.network.numberOfStalls)
    }

    private var renditionValue: String {
        let resolution = snapshot.playback.resolution
        let rate = snapshot.network.indicatedBitRate
            ?? snapshot.network.observedBitRate
        switch (resolution, rate) {
        case let (resolution?, rate?):
            return "\(resolution) · \(PlaybackDiagnosticsFormat.bitRate(rate))"
        case let (resolution?, nil):
            return resolution
        case let (nil, rate?):
            return PlaybackDiagnosticsFormat.bitRate(rate)
        case (nil, nil):
            return "Not measured"
        }
    }

    private func severityIcon(_ level: PlaybackDiagnosticsLevel) -> String {
        switch level {
        case .observation:
            return "info.circle"
        case .notice:
            return "waveform.path.ecg"
        case .warning:
            return "exclamationmark.triangle"
        case .critical:
            return "xmark.octagon"
        }
    }

    private func toggleLive() {
        isLive.toggle()
        if isLive {
            displayTime = Date()
            refresh()
        }
    }

    private func captureBookmark() {
        if let bookmark = playerManager.capturePlaybackDiagnosticsBookmark() {
            showFeedback(
                "Moment saved · \(String(bookmark.id.uuidString.prefix(8)))",
                succeeded: true
            )
            if isLive {
                displayTime = Date()
                refresh()
            }
        } else {
            showFeedback("No active playback to save", succeeded: false)
        }
    }

    private func copyReport() {
        let report = playerManager.fetchPlaybackDiagnostics().report()
        NSPasteboard.general.clearContents()
        let copied = NSPasteboard.general.setString(report, forType: .string)
        showFeedback(
            copied ? "Privacy-safe report copied" : "Report could not be copied",
            succeeded: copied
        )
        if copied {
            playbackDiagnosticsLogger.info("privacy-safe playback report copied")
        } else {
            playbackDiagnosticsLogger.error("playback report copy failed")
        }
    }

    private func refresh() {
        snapshot = playerManager.fetchPlaybackDiagnostics()
        sampledContentTitle = Self.contentTitle(from: playerManager)

        let incidentIDs = Set(snapshot.storyboard.incidents.map(\.id))
        if selectedIncidentID.map({ incidentIDs.contains($0) }) != true {
            selectedIncidentID = sortedIncidents.first?.id
        }
    }

    private func showFeedback(_ message: String, succeeded: Bool) {
        let next = DiagnosticsFeedback(message: message, succeeded: succeeded)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            feedback = next
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard feedback?.id == next.id else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                feedback = nil
            }
        }
    }

    private static func contentTitle(from playerManager: PlayerManager) -> String {
        let title = playerManager.playerItem?.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title?.isEmpty == false ? title! : "Current playback session"
    }
}
#endif
