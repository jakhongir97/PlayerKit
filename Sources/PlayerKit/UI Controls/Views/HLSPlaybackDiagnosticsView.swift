#if os(macOS)
import AppKit
import Combine
import OSLog
import SwiftUI

private let playbackDiagnosticsLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.netco.itv",
    category: "PlaybackHealth"
)

private enum PlaybackDiagnosticsPage: CaseIterable, Identifiable {
    case overview
    case events
    case technical

    var id: Self { self }

    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .events:
            return "Timeline"
        case .technical:
            return "Details"
        }
    }

    var subtitle: String {
        switch self {
        case .overview:
            return "Live playback health"
        case .events:
            return "Saved evidence and signals"
        case .technical:
            return "Session metrics"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "waveform.path.ecg"
        case .events:
            return "clock.arrow.circlepath"
        case .technical:
            return "slider.horizontal.3"
        }
    }
}

private enum PlaybackDiagnosticsHistoryFilter: CaseIterable, Identifiable {
    case all
    case moments
    case signals
    case errors

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .moments:
            return "Saved"
        case .signals:
            return "Signals"
        case .errors:
            return "Errors"
        }
    }
}

private enum PlaybackDiagnosticsTechnicalSection: CaseIterable, Identifiable {
    case monitoring
    case playback
    case startup
    case rendition
    case delivery
    case requests
    case tracks
    case collection

    var id: Self { self }

    var title: String {
        switch self {
        case .monitoring:
            return "Monitoring"
        case .playback:
            return "Playback & Buffer"
        case .startup:
            return "Startup & Seeking"
        case .rendition:
            return "Picture Quality"
        case .delivery:
            return "Network Delivery"
        case .requests:
            return "Recent Requests"
        case .tracks:
            return "Audio & Subtitles"
        case .collection:
            return "Data Collection"
        }
    }

    var subtitle: String {
        switch self {
        case .monitoring:
            return "Observer and coverage"
        case .playback:
            return "Player state and runway"
        case .startup:
            return "Waits, starts, and seeks"
        case .rendition:
            return "Resolution and adaptation"
        case .delivery:
            return "Traffic and stalls"
        case .requests:
            return "Privacy-safe request trace"
        case .tracks:
            return "Selected media tracks"
        case .collection:
            return "Retention and classifier"
        }
    }

    var systemImage: String {
        switch self {
        case .monitoring:
            return "point.3.connected.trianglepath.dotted"
        case .playback:
            return "play.rectangle"
        case .startup:
            return "timer"
        case .rendition:
            return "chart.line.uptrend.xyaxis"
        case .delivery:
            return "network"
        case .requests:
            return "list.bullet.rectangle"
        case .tracks:
            return "captions.bubble"
        case .collection:
            return "tray.full"
        }
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
            return "No problem detected right now"
        case let .needsAttention(level):
            return level >= .warning ? "Playback may be unstable" : "Playback needs attention"
        case .waiting:
            return "Playback is waiting"
        case .failed:
            return "Playback failed"
        case .nothingPlaying:
            return "Nothing is playing"
        case .checkLimited:
            return "Playback check is limited"
        case .detailsUnavailable:
            return "Playback details unavailable"
        }
    }
}

private struct DiagnosticsCaptureFeedback {
    let id = UUID()
    let message: String
    let succeeded: Bool
}

private struct DiagnosticsErrorRow: Identifiable {
    let id: String
    let error: PlaybackDiagnosticsError
}

private struct DiagnosticsHealthEventRow: Identifiable {
    struct ID: Hashable {
        let event: PlaybackHealthEvent
        let occurrence: Int
    }

    let id: ID
    let event: PlaybackHealthEvent
}

private struct DiagnosticsTrackRow: Identifiable {
    let id: String
    let track: PlaybackDiagnosticsTrack
}

public struct HLSPlaybackDiagnosticsView: View {
    @ObservedObject private var playerManager: PlayerManager
    @State private var snapshot: PlaybackDiagnosticsSnapshot
    @State private var sampledContentTitle: String
    @State private var selectedPage: PlaybackDiagnosticsPage? = .overview
    @State private var selectedHistoryFilter: PlaybackDiagnosticsHistoryFilter = .all
    @State private var selectedTechnicalSection: PlaybackDiagnosticsTechnicalSection? = .monitoring
    @State private var isLive = true
    @State private var displayTime = Date()
    @State private var didCopy = false
    @State private var captureFeedback: DiagnosticsCaptureFeedback?
    @State private var showsClearConfirmation = false
    @State private var showsCoverage = false

    private let keepsPlayerControlsVisible: Bool
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(
        playerManager: PlayerManager,
        keepsPlayerControlsVisible: Bool = true
    ) {
        self.playerManager = playerManager
        self.keepsPlayerControlsVisible = keepsPlayerControlsVisible
        _snapshot = State(initialValue: playerManager.fetchPlaybackDiagnostics())
        _sampledContentTitle = State(initialValue: Self.contentTitle(from: playerManager))
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 184, ideal: 196, max: 210)
        } detail: {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)

                Divider()

                selectedPageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(
            minWidth: 760,
            idealWidth: 980,
            maxWidth: .infinity,
            minHeight: 500,
            idealHeight: 720,
            maxHeight: .infinity
        )
        .overlay(alignment: .bottom) {
            if let captureFeedback {
                Label(
                    captureFeedback.message,
                    systemImage: captureFeedback.succeeded
                        ? "checkmark.circle.fill"
                        : "xmark.circle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(captureFeedback.succeeded ? Color.green : Color.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 4, y: 2)
                .padding(.bottom, 12)
                .allowsHitTesting(false)
                .accessibilityIdentifier("player.diagnostics.capture.feedback")
            }
        }
        .onAppear {
            if keepsPlayerControlsVisible {
                playerManager.userInteracting = true
                playerManager.userInteracted()
            }
            playbackDiagnosticsLogger.info("diagnostics dashboard opened")
            refresh()
        }
        .onDisappear {
            if keepsPlayerControlsVisible {
                playerManager.userInteracting = false
                playerManager.userInteracted()
            }
            playbackDiagnosticsLogger.info("diagnostics dashboard closed")
        }
        .onReceive(timer) { now in
            displayTime = now
            if isLive {
                refresh()
            }
        }
        .confirmationDialog(
            "Clear saved moments and retained signals?",
            isPresented: $showsClearConfirmation
        ) {
            Button("Clear Saved Moments & Signals", role: .destructive) {
                playerManager.clearPlaybackDiagnosticsEvents()
                playbackDiagnosticsLogger.info("diagnostics dashboard cleared saved moments and retained signals")
                refresh()
            }
            .accessibilityIdentifier("player.diagnostics.clear.confirm")
        } message: {
            Text(
                "This removes saved moments and retained signal rows. Aggregate counters, AVFoundation logs, " +
                "and observer totals remain for the current playback session."
            )
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    statusSymbol

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Playback Monitor")
                            .font(.headline)

                        Text(currentPresentationStatus.title)
                            .font(.caption)
                            .foregroundStyle(currentStatusColor)
                            .lineLimit(2)
                    }
                }

                Text(contentTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(contentTitle)
            }
            .padding(16)
            .accessibilityElement(children: .combine)

            Divider()

            List(selection: $selectedPage) {
                Section("Monitor") {
                    ForEach(PlaybackDiagnosticsPage.allCases) { page in
                        HStack(spacing: 10) {
                            Image(systemName: page.systemImage)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(page.title)
                                    .lineLimit(1)
                                Text(page.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 4)

                            if let count = pageBadgeCount(page), count > 0 {
                                Text("\(count)")
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(page)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(page.title))
                        .accessibilityValue(Text(pageAccessibilityValue(page)))
                    }
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("player.diagnostics.page")

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Label(monitoringStatusTitle, systemImage: monitoringStatusIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(coverageStatusColor)

                Text(sampleStateText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help(sampleStateAccessibilityText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    private var observerCoverageSummary: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: monitoringStatusIcon)
                .foregroundStyle(coverageStatusColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(monitoringStatusTitle)
                    .font(.caption.weight(.semibold))

                Text("\(signalPath) · \(hlsEvidenceText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(coverageLimitationText)
                    .font(.caption)
                    .foregroundStyle(coverageStatusColor)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Monitoring coverage")
        .accessibilityValue(
            "\(snapshot.session.availability.title). \(signalPath). " +
            "\(hlsEvidenceText). \(coverageLimitationText)."
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 7) {
                    Text((selectedPage ?? .overview).title)
                        .font(.title2.weight(.semibold))

                    Text("EXPERIMENTAL")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }

                Spacer(minLength: 12)

                Toggle(isOn: liveBinding) {
                    Label(
                        isLive ? "Live" : "Paused",
                        systemImage: isLive ? "dot.radiowaves.left.and.right" : "pause.fill"
                    )
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help(
                    isLive
                        ? "Pause automatic updates to inspect this sample"
                        : "Resume one-second automatic updates"
                )
                .accessibilityIdentifier("player.diagnostics.live")

                Button {
                    refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .keyboardShortcut("r", modifiers: .command)
                .help(isLive ? "Refresh now" : "Refresh the paused snapshot")
                .accessibilityIdentifier("player.diagnostics.refresh")
            }

            HStack(alignment: .center, spacing: 10) {
                Label("Privacy-safe report", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Copied reports never include URLs, headers, or tokens")

                Spacer(minLength: 8)

                Button {
                    captureIncident()
                } label: {
                    Label("Save Moment", systemImage: "camera.metering.partial")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .help("Save a private playback snapshot for this session (⇧⌘I)")
                .disabled(!canCaptureIncident)
                .accessibilityIdentifier("player.diagnostics.capture")

                Button {
                    copyReport()
                } label: {
                    Label(
                        didCopy ? "Copied" : "Copy Report",
                        systemImage: didCopy ? "checkmark" : "doc.on.doc"
                    )
                }
                .frame(minWidth: 112)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help(
                    didCopy
                        ? "Privacy-safe report copied"
                        : "Copy this sample without URLs, headers, or tokens"
                )
                .accessibilityIdentifier("player.diagnostics.copy")
            }
        }
    }

    @ViewBuilder
    private var selectedPageContent: some View {
        switch selectedPage ?? .overview {
        case .overview:
            overviewPage
        case .events:
            eventsPage
        case .technical:
            technicalPage
        }
    }

    private var overviewPage: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if snapshot.session.availability == .noPlayerItem {
                    noPlaybackState
                } else {
                    playbackStatusSummary
                    quickMetrics
                    sessionActivity

                    if !activeIssues.isEmpty {
                        diagnosticsSection("Needs Attention Now", systemImage: "waveform.path.ecg") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(activeIssues) { issue in
                                    issueCard(issue)
                                }
                            }
                        }
                    }

                    diagnosticsSection("Earlier This Session", systemImage: "clock.arrow.circlepath") {
                        if historicalIssues.isEmpty {
                            emptyState("No earlier delivery finding is retained for this session.")
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(historicalIssues) { issue in
                                    issueCard(issue)
                                }
                            }
                        }
                    }
                }

                GroupBox {
                    DisclosureGroup(isExpanded: $showsCoverage) {
                        VStack(alignment: .leading, spacing: 10) {
                            observerCoverageSummary

                            Divider()

                            Text(
                                "This check can detect request failures, stalls, buffer pressure, error logs, and " +
                                "delivery or picture-quality changes. It cannot recognize every media defect; for " +
                                "example, a successful response that contains silence may produce no warning."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                            ForEach(coverageIssues) { issue in
                                issueCard(issue)
                            }
                        }
                        .padding(.top, 10)
                    } label: {
                        Label("About This Check", systemImage: "eye")
                            .font(.callout.weight(.semibold))
                    }
                }
            }
            .padding(16)
        }
    }

    private var noPlaybackState: some View {
        ContentUnavailableView {
            Label("Start a video to monitor playback", systemImage: "play.slash")
        } description: {
            Text("Live health, buffering, connection, and delivery details will appear here.")
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var playbackStatusSummary: some View {
        HStack(alignment: .top, spacing: 14) {
            statusSymbol

            VStack(alignment: .leading, spacing: 5) {
                Text(currentPresentationStatus.title)
                    .font(.title2.weight(.semibold))

                Text(currentStatusDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(sessionEvidenceHeadline)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                if snapshot.session.availability == .startingAVMetrics {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(monitoringStatusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(coverageStatusColor)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(coverageStatusColor.opacity(0.10), in: Capsule())
        }
        .padding(16)
        .background(currentStatusColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(currentStatusColor.opacity(0.20), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var quickMetrics: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 10)],
            alignment: .leading,
            spacing: 10
        ) {
            metricCard(
                "Playback",
                value: friendlyPlaybackState,
                detail: "\(time(snapshot.playback.currentTime)) / \(time(snapshot.playback.duration))",
                systemImage: "play.rectangle"
            )
            metricCard(
                "Buffer Ahead",
                value: seconds(snapshot.playback.bufferHeadroom),
                detail: bufferMetricDetail,
                systemImage: "gauge.with.dots.needle.50percent"
            )
            metricCard(
                "Connection Headroom",
                value: throughputMargin,
                detail: "\(bitRate(snapshot.network.observedBitRate)) available · " +
                    "\(bitRate(snapshot.network.indicatedBitRate)) needed",
                systemImage: "network"
            )
            metricCard(
                "Picture Quality",
                value: snapshot.playback.resolution ?? "Unknown",
                detail: frequency(snapshot.playback.frameRate),
                systemImage: "rectangle.inset.filled"
            )
        }
    }

    private var sessionActivity: some View {
        diagnosticsSection("Session Activity", systemImage: "chart.bar.xaxis") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: 16)],
                alignment: .leading,
                spacing: 12
            ) {
                activityMetric(
                    "Saved moments",
                    value: snapshot.incidents.count,
                    systemImage: "camera.viewfinder"
                )
                activityMetric(
                    "Signals retained",
                    value: snapshot.recentHealthEvents.count,
                    systemImage: "waveform.badge.exclamationmark"
                )
                activityMetric(
                    "Error entries",
                    value: snapshot.recentErrors.count,
                    systemImage: "exclamationmark.triangle"
                )
                activityMetric(
                    "Requests observed",
                    value: snapshot.monitor.map {
                        $0.observedHLSRequestCount
                    } ?? snapshot.network.mediaRequestCount ?? 0,
                    systemImage: "arrow.left.arrow.right"
                )
            }
        }
    }

    private func activityMetric(
        _ title: String,
        value: Int,
        systemImage: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(value.formatted())
                    .font(.headline.monospacedDigit())
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value.formatted())
    }

    private func metricCard(
        _ title: String,
        value: String,
        detail: String,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value). \(detail)")
    }

    private var eventsPage: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Playback evidence")
                                .font(.title3.weight(.semibold))
                            Text("Review the current session or save the exact moment something feels wrong.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            captureIncident()
                        } label: {
                            Label("Save Current Moment", systemImage: "camera.metering.partial")
                        }
                        .disabled(!canCaptureIncident)
                        .help("Save privacy-safe playback, buffer, connection, and selected-audio state")
                        .accessibilityIdentifier("player.diagnostics.capture.events")
                    }

                    Picker("Timeline filter", selection: $selectedHistoryFilter) {
                        ForEach(PlaybackDiagnosticsHistoryFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 420)
                    .accessibilityIdentifier("player.diagnostics.timeline.filter")

                    HStack(spacing: 24) {
                        activityMetric(
                            "Saved",
                            value: snapshot.incidents.count,
                            systemImage: "camera.viewfinder"
                        )
                        activityMetric(
                            "Signals",
                            value: snapshot.recentHealthEvents.count,
                            systemImage: "waveform.badge.exclamationmark"
                        )
                        activityMetric(
                            "Errors",
                            value: snapshot.recentErrors.count,
                            systemImage: "exclamationmark.triangle"
                        )
                    }
                }
                .padding(16)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }

                filteredHistoryContent

                HStack {
                    Text(
                        "Clearing removes saved moments and retained signals only. Session totals and system logs remain."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button("Clear Saved Moments & Signals…", role: .destructive) {
                        showsClearConfirmation = true
                    }
                    .disabled(snapshot.recentHealthEvents.isEmpty && snapshot.incidents.isEmpty)
                    .accessibilityIdentifier("player.diagnostics.clear")
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var filteredHistoryContent: some View {
        switch selectedHistoryFilter {
        case .all:
            if snapshot.monitor?.terminalFailure != nil {
                terminalFailureSection
            }
            if snapshot.monitor?.latestFailureContext != nil {
                latestFailedRequestSection
            }
            incidentsSection
            healthEventsSection
            errorsSection
        case .moments:
            incidentsSection
        case .signals:
            healthEventsSection
        case .errors:
            if snapshot.monitor?.terminalFailure != nil {
                terminalFailureSection
            }
            if snapshot.monitor?.latestFailureContext != nil {
                latestFailedRequestSection
            }
            errorsSection
        }
    }

    private var incidentsSection: some View {
        diagnosticsSection(
            "Saved Moments · \(snapshot.incidents.count) of 20",
            systemImage: "camera.viewfinder"
        ) {
            if snapshot.incidents.isEmpty {
                emptyState("No moment has been saved for the current item.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(snapshot.incidents.reversed())) { incident in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(
                                    "Buffer \(seconds(incident.bufferHeadroom)) · " +
                                    "\(incident.isPlaybackBufferEmpty ? "empty" : "not empty") · " +
                                    "\(incident.isPlaybackLikelyToKeepUp ? "expected to keep up" : "keep-up uncertain")"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                Text(
                                    "Picture \(incident.resolution ?? "unknown") · " +
                                    "\(frequency(incident.frameRate)) · " +
                                    "connection \(bitRate(incident.observedBitRate)) / " +
                                    "needed \(bitRate(incident.indicatedBitRate))"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                Text(
                                    "Requests \(incident.observedHLSRequestCount) · " +
                                    "failed \(incident.failedHLSRequestCount) · " +
                                    "stalls \(incident.metricStallCount) metric / " +
                                    "\(integer(incident.accessLogStallCount)) system · " +
                                    "waits \(incident.postStartWaitCount) playback / " +
                                    "\(incident.seekWaitCount) seek"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                Text(
                                    "Evidence \(incident.retainedHealthEventCount) retained signal(s) · " +
                                    "\(incident.errorLogEventCount) error-log entry/entries"
                                )
                                .font(.caption2)
                                .foregroundStyle(.tertiary)

                                if let waitingReason = incident.waitingReason {
                                    Text("Waiting reason: \(waitingReason)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if let track = incident.selectedAudioTrack {
                                    Text(
                                        "Audio: \(track.name)" +
                                        (track.languageCode.map { " · \($0)" } ?? "")
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Label("Saved moment", systemImage: "pin.fill")
                                        .font(.caption.weight(.semibold))

                                    Text(
                                        "\(friendlyItemStatus(incident.itemStatus)) · " +
                                        "\(friendlyTimeControlStatus(incident.timeControlStatus)) · " +
                                        "position \(time(incident.mediaTime))"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                timestampText(incident.capturedAt)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var healthEventsSection: some View {
        diagnosticsSection(
            "Automatic Delivery Signals · \(snapshot.history.retainedCount) of \(snapshot.history.receivedCount)",
            systemImage: "waveform.badge.exclamationmark"
        ) {
            if snapshot.recentHealthEvents.isEmpty {
                emptyState("No automatic delivery signal is retained for this playback session.")
            } else {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(healthEventRows.reversed())) { row in
                            let event = row.event
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 7) {
                                    Text(friendlySignal(event.signalKind))
                                        .font(.caption.weight(.semibold))

                                    Text(
                                        "Signal confidence · " +
                                        friendlyConfidence(event.confidence)
                                    )
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(color(for: event.confidence))

                                    Spacer()

                                    timestampText(event.occurredAt)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Text(
                                    "\(friendlyMediaType(event.mediaType)) · position \(time(event.mediaTime)) · " +
                                    "\(friendlyRecovery(event.didRecover))"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                Text(
                                    "\(event.errorDomain ?? "No listed domain") · " +
                                    "\(event.errorCode.map(String.init) ?? "no code")"
                                )
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)

                                if let track = event.selectedAudioTrack {
                                    HStack(spacing: 4) {
                                        Text(
                                            "Audio: \(track.displayName ?? "Unnamed")" +
                                            (track.languageCode.map { " · \($0)" } ?? "")
                                        )

                                        Text("· \(track.identifier)")
                                            .textSelection(.enabled)
                                            .accessibilityHidden(true)
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(10)
                            .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Show \(snapshot.recentHealthEvents.count) retained signal" +
                         "\(snapshot.recentHealthEvents.count == 1 ? "" : "s")")
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }

    private var errorsSection: some View {
        diagnosticsSection(
            "System Error Codes · \(snapshot.recentErrors.count) shown · " +
            "\(snapshot.errorLogEventCount) log total",
            systemImage: "exclamationmark.octagon"
        ) {
            if errorRows.isEmpty {
                emptyState("No error-log entry was observed for the current item.")
            } else {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(errorRows.reversed()) { row in
                            LabeledContent {
                                Text("\(row.error.domain ?? "Unlisted domain") · \(row.error.code)")
                                    .monospaced()
                                    .textSelection(.enabled)
                            } label: {
                                if let occurredAt = row.error.occurredAt {
                                    timestampText(occurredAt)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Item error")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Show \(errorRows.count) error code\(errorRows.count == 1 ? "" : "s")")
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }

    private var latestFailedRequestSection: some View {
        diagnosticsSection("Latest Delivery Failure", systemImage: "clock.badge.exclamationmark") {
            if let context = snapshot.monitor?.latestFailureContext {
                diagnosticsRows {
                    diagnosticsRow("Signal", friendlySignal(context.signalKind))
                    diagnosticsRow("Media", friendlyMediaType(context.mediaType))
                    diagnosticsTimestampRow("Occurred", context.occurredAt)
                    diagnosticsRow("HTTP status", integer(context.httpStatusCode))

                    DisclosureGroup("Technical request details") {
                        diagnosticsRows {
                            diagnosticsRow("Request total", seconds(context.requestDuration))
                            diagnosticsRow("Time to first byte", seconds(context.timeToFirstByte))
                            diagnosticsRow("Response transfer", seconds(context.responseDuration))
                            diagnosticsRow("Read from cache", optionalYesNo(context.wasReadFromCache))
                            diagnosticsRow("Segment duration", seconds(context.segmentDuration))
                            diagnosticsRow(
                                "Requested byte-range length",
                                context.requestedByteRangeLength.map {
                                    ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
                                } ?? "Unknown"
                            )
                            diagnosticsRow("Response body bytes", bytes(context.responseBodyBytes))
                            diagnosticsRow("Redirects", integer(context.redirectCount))
                            diagnosticsRow("Network protocol", context.networkProtocol ?? "Unknown")
                            diagnosticsRow("DNS lookup", seconds(context.dnsDuration))
                            diagnosticsRow("Connection", seconds(context.connectDuration))
                            diagnosticsRow("TLS handshake", seconds(context.tlsDuration))
                        }
                        .padding(.top, 8)
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
    }

    private var terminalFailureSection: some View {
        diagnosticsSection("Playback Stopped", systemImage: "xmark.octagon") {
            if let failure = snapshot.monitor?.terminalFailure {
                diagnosticsRows {
                    diagnosticsTimestampRow("Occurred", failure.occurredAt)
                    diagnosticsRow("Playback position", time(failure.mediaTime))
                    diagnosticsRow("Error domain", failure.error.domain ?? "Unlisted domain")
                    diagnosticsRow("Error code", "\(failure.error.code)")
                }

                Text("AVFoundation marked the current item as terminally failed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
    }

    private var technicalPage: some View {
        let section = selectedTechnicalSection ?? .monitoring
        return HStack(spacing: 0) {
            List(selection: $selectedTechnicalSection) {
                Section("Inspect") {
                    ForEach(PlaybackDiagnosticsTechnicalSection.allCases) { section in
                        HStack(spacing: 9) {
                            Image(systemName: section.systemImage)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(section.title)
                                    .lineLimit(1)
                                Text(section.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .tag(section)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(section.title))
                        .accessibilityValue(Text(section.subtitle))
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(width: 220)
            .accessibilityIdentifier("player.diagnostics.details.section")

            Divider()

            ScrollView {
                VStack(alignment: .leading) {
                    diagnosticsSection(
                        section == .requests ? requestTraceTitle : section.title,
                        systemImage: section.systemImage
                    ) {
                        Text(section.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)

                        selectedTechnicalDetails
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var selectedTechnicalDetails: some View {
        switch selectedTechnicalSection ?? .monitoring {
        case .monitoring:
            observerDetails
        case .playback:
            playbackDetails
        case .startup:
            startupAndSeekDetails
        case .rendition:
            renditionDetails
        case .delivery:
            deliveryDetails
        case .requests:
            requestTraceDetails
        case .tracks:
            tracksDetails
        case .collection:
            classifierDetails
        }
    }

    private var observerDetails: some View {
        diagnosticsRows {
            diagnosticsRow("Observer", snapshot.session.availability.title)
            diagnosticsRow("Backend", snapshot.session.backend)
            diagnosticsRow("Monitor attached", yesNo(snapshot.session.monitorAttached))
            diagnosticsRow("Signal path", signalPath)
            diagnosticsRow("Session", snapshot.session.sessionID?.uuidString ?? "Unavailable")
            diagnosticsRow(
                "Asset ID / fingerprint",
                snapshot.session.assetIdentifier ?? "Missing",
                accessibilityValue: assetIdentifierAccessibilityValue
            )
            diagnosticsRow("HLS identified", optionalYesNo(snapshot.playback.isLikelyHLS))
            diagnosticsTimestampRow("Captured", snapshot.session.capturedAt)

            if let monitor = snapshot.monitor {
                diagnosticsRow("Metric stream", friendlyStreamState(monitor.streamState))
                diagnosticsRow(
                    "Fallback reason",
                    monitor.fallbackReason.map(friendlyFallbackReason) ?? "None"
                )
                diagnosticsRow(
                    "Stream failure",
                    monitor.streamFailure.map {
                        "\($0.domain ?? "Unlisted domain") · \($0.code)"
                    } ?? "None"
                )
                diagnosticsRow("Playlist requests observed", "\(monitor.playlistRequestCount)")
                diagnosticsRow("Segment requests observed", "\(monitor.segmentRequestCount)")
                diagnosticsRow("Successful requests observed, not retained", "\(monitor.healthyDropCount)")
                diagnosticsRow(
                    "Failed playlist / segment",
                    "\(monitor.failedPlaylistRequestCount) / \(monitor.failedSegmentRequestCount)"
                )
                diagnosticsRow(
                    "Audio / video / muxed / unknown",
                    "\(monitor.audioRequestCount) / \(monitor.videoRequestCount) / " +
                    "\(monitor.muxedRequestCount) / \(monitor.unknownRequestCount)"
                )
                diagnosticsRow("Metric stalls", "\(monitor.stallCount)")
            }
        }
    }

    private var playbackDetails: some View {
        diagnosticsRows {
            diagnosticsRow("Item status", friendlyItemStatus(snapshot.playback.itemStatus))
            diagnosticsRow("Time control", friendlyTimeControlStatus(snapshot.playback.timeControlStatus))
            diagnosticsRow("Waiting reason", snapshot.playback.waitingReason ?? "None")
            diagnosticsRow("Rate", String(format: "%.2f×", snapshot.playback.rate))
            diagnosticsRow("Position", time(snapshot.playback.currentTime))
            diagnosticsRow("Duration", time(snapshot.playback.duration))
            diagnosticsRow("Buffered until", time(snapshot.playback.bufferedUntil))
            diagnosticsRow("Buffer headroom", seconds(snapshot.playback.bufferHeadroom))
            diagnosticsRow("Likely to keep up", yesNo(snapshot.playback.isPlaybackLikelyToKeepUp))
            diagnosticsRow(
                "Buffer empty / full",
                "\(yesNo(snapshot.playback.isPlaybackBufferEmpty)) / " +
                "\(yesNo(snapshot.playback.isPlaybackBufferFull))"
            )
            diagnosticsRow(
                "Loaded / seekable ranges",
                "\(snapshot.playback.loadedRangeCount) / \(snapshot.playback.seekableRangeCount)"
            )
            diagnosticsRow(
                "Automatic stall waiting",
                yesNo(snapshot.playback.automaticallyWaitsToMinimizeStalling)
            )
            diagnosticsRow("Muted", yesNo(snapshot.playback.isMuted))
            diagnosticsRow("Volume", String(format: "%.0f%%", snapshot.playback.volume * 100))
            diagnosticsRow("Playback type", snapshot.playback.playbackType ?? "Unknown")
            diagnosticsRow(
                "Forward buffer preference",
                snapshot.playback.preferredForwardBufferDuration > 0
                    ? seconds(snapshot.playback.preferredForwardBufferDuration)
                    : "Automatic"
            )

            if let waiting = snapshot.monitor?.waiting {
                diagnosticsRow("Initial waits", "\(waiting.initialWaitCount)")
                diagnosticsRow("Post-start waits", "\(waiting.postStartWaitCount)")
                diagnosticsRow("Seek waits", "\(waiting.seekWaitCount)")
                diagnosticsRow(
                    "Current wait kind",
                    waiting.currentKind.map(friendlyWaitKind) ?? "None"
                )
                diagnosticsRow("Current wait duration", seconds(waiting.currentWaitDuration))
                diagnosticsRow("Total wait duration", seconds(waiting.totalWaitDuration))
                diagnosticsRow("Longest wait", seconds(waiting.longestWaitDuration))
                diagnosticsRow("Last wait duration", seconds(waiting.lastWaitDuration))
                diagnosticsRow("Last wait reason", waiting.lastReason ?? "None")
                diagnosticsTimestampRow("Last wait ended", waiting.lastEndedAt)
            }

            if let naturalEnd = snapshot.monitor?.naturalEnd {
                diagnosticsRow("Natural end observed", "Yes · explicit did-play-to-end event")
                diagnosticsTimestampRow("Natural end occurred", naturalEnd.occurredAt)
                diagnosticsRow("Natural end media time", time(naturalEnd.mediaTime))
            } else {
                diagnosticsRow("Natural end observed", "No")
            }
        }
    }

    private var renditionDetails: some View {
        diagnosticsRows {
            diagnosticsRow("Resolution", snapshot.playback.resolution ?? "Unknown")
            diagnosticsRow("Frame rate", frequency(snapshot.playback.frameRate))
            diagnosticsRow("Observed throughput", bitRate(snapshot.network.observedBitRate))
            diagnosticsRow("Indicated bitrate", bitRate(snapshot.network.indicatedBitRate))
            diagnosticsRow("Indicated average", bitRate(snapshot.network.indicatedAverageBitRate))
            diagnosticsRow("Average video bitrate", bitRate(snapshot.network.averageVideoBitRate))
            diagnosticsRow("Average audio bitrate", bitRate(snapshot.network.averageAudioBitRate))
            diagnosticsRow(
                "Throughput deviation",
                bitRate(snapshot.network.observedBitRateStandardDeviation)
            )
            diagnosticsRow("Last switch bitrate", bitRate(snapshot.network.switchBitRate))
            diagnosticsRow(
                "Preferred peak bitrate",
                snapshot.playback.preferredPeakBitRate > 0
                    ? bitRate(snapshot.playback.preferredPeakBitRate)
                    : "Automatic"
            )
            diagnosticsRow(
                "Maximum resolution",
                snapshot.playback.preferredMaximumResolution ?? "Automatic"
            )

            if let switches = snapshot.monitor?.variantSwitches {
                diagnosticsRow("Variant switches", "\(switches.totalCount)")
                diagnosticsRow(
                    "Succeeded / failed",
                    "\(switches.succeededCount) / \(switches.failedCount)"
                )
                diagnosticsRow(
                    "Successful up / down / lateral / unknown",
                    "\(switches.upCount) / \(switches.downCount) / " +
                    "\(switches.lateralCount) / \(switches.unknownDirectionCount)"
                )
                diagnosticsTimestampRow("Latest switch", switches.latestOccurredAt, missing: "None")
                diagnosticsRow(
                    "Latest switch outcome",
                    switches.latestSucceeded.map { $0 ? "Succeeded" : "Failed" } ?? "Unknown"
                )
                diagnosticsRow("Latest switch from", variantDescription(switches.latestFrom))
                diagnosticsRow("Latest switch to", variantDescription(switches.latestTo))
            }
        }
    }

    private var startupAndSeekDetails: some View {
        diagnosticsRows {
            if let monitor = snapshot.monitor {
                let likely = monitor.likelyToKeepUp
                diagnosticsRow("Likely-to-keep-up events", "\(likely.eventCount)")
                diagnosticsRow(
                    "Initial time to likely-to-keep-up",
                    seconds(likely.initial?.timeTaken)
                )
                diagnosticsRow(
                    "Initial loaded media",
                    seconds(likely.initial?.loadedRangeDuration)
                )
                diagnosticsRow(
                    "Latest recovery time",
                    seconds(likely.latest?.timeTaken)
                )
                diagnosticsRow(
                    "Latest loaded media",
                    seconds(likely.latest?.loadedRangeDuration)
                )
                diagnosticsTimestampRow(
                    "Latest keep-up event",
                    likely.latest?.occurredAt,
                    missing: "None"
                )

                if let initialRequests = likely.initialRequests {
                    diagnosticsRow(
                        "Startup playlist requests / time",
                        requestTiming(initialRequests.playlists)
                    )
                    diagnosticsRow(
                        "Startup segment requests / time",
                        requestTiming(initialRequests.segments)
                    )
                    diagnosticsRow(
                        "Startup content-key requests / time",
                        requestTiming(initialRequests.contentKeys)
                    )
                } else {
                    diagnosticsRow("Startup request breakdown", "Not emitted yet")
                }

                Divider()

                diagnosticsRow("Seek starts", "\(monitor.seeks.startedCount)")
                diagnosticsRow("Seek completions", "\(monitor.seeks.completedCount)")
                diagnosticsRow("Seeks still in progress", "\(monitor.seeks.inProgressCount)")
                diagnosticsRow(
                    "Completed in / outside / unknown buffer",
                    "\(monitor.seeks.inBufferCount) / \(monitor.seeks.outsideBufferCount) / " +
                    "\(monitor.seeks.unknownBufferCount)"
                )
                diagnosticsRow(
                    "Latest seek used buffered media",
                    optionalYesNo(monitor.seeks.latestDidSeekInBuffer)
                )
                diagnosticsTimestampRow(
                    "Latest seek completed",
                    monitor.seeks.latestCompletedAt,
                    missing: "None"
                )

                Divider()

                diagnosticsRow("Content-key requests", "\(monitor.contentKeys.totalCount)")
                diagnosticsRow(
                    "Content-key succeeded / failed / client-initiated",
                    "\(monitor.contentKeys.succeededCount) / \(monitor.contentKeys.failedCount) / " +
                    "\(monitor.contentKeys.clientInitiatedCount)"
                )
                diagnosticsRow(
                    "Key requests · audio / video / muxed / unknown",
                    "\(monitor.contentKeys.audio.totalCount) / \(monitor.contentKeys.video.totalCount) / " +
                    "\(monitor.contentKeys.muxed.totalCount) / \(monitor.contentKeys.unknown.totalCount)"
                )

                Divider()

                if let summary = monitor.playbackSummary {
                    diagnosticsTimestampRow("Summary emitted", summary.occurredAt)
                    diagnosticsRow(
                        "Playback / initial startup / stall recovery",
                        "\(seconds(summary.playbackDuration.map(Double.init))) / " +
                        "\(seconds(summary.timeSpentInInitialStartup)) / " +
                        "\(seconds(summary.timeSpentRecoveringFromStall))"
                    )
                    diagnosticsRow(
                        "Summary requests / stalls / variant switches",
                        "\(integer(summary.mediaResourceRequestCount)) / " +
                        "\(integer(summary.stallCount)) / " +
                        "\(integer(summary.variantSwitchCount))"
                    )
                    diagnosticsRow(
                        "Summary recoverable errors",
                        integer(summary.recoverableErrorCount)
                    )
                    diagnosticsRow(
                        "Time-weighted average / peak bitrate",
                        "\(summary.timeWeightedAverageBitrate.map { bitRate(Double($0)) } ?? "Unknown") / " +
                        "\(summary.timeWeightedPeakBitrate.map { bitRate(Double($0)) } ?? "Unknown")"
                    )
                    diagnosticsRow(
                        "Summary error",
                        summary.error.map {
                            "\($0.domain ?? "Unlisted domain") · \($0.code) · " +
                            friendlyRecovery(summary.errorDidRecover)
                        } ?? "None"
                    )
                } else {
                    diagnosticsRow(
                        "Playback summary",
                        "Pending · AVFoundation normally emits this near session end"
                    )
                }
            } else {
                diagnosticsRow("Advanced metric state", "Unavailable")
            }
        }
    }

    private var deliveryDetails: some View {
        diagnosticsRows {
            diagnosticsRow("Total access-log periods", "\(snapshot.network.accessLogEventCount)")
            diagnosticsRow("Media requests", integer(snapshot.network.mediaRequestCount))
            diagnosticsRow("Bytes transferred", bytes(snapshot.network.bytesTransferred))
            diagnosticsRow("Transfer time", seconds(snapshot.network.transferDuration))
            diagnosticsRow("Downloaded media", seconds(snapshot.network.segmentsDownloadedDuration))
            diagnosticsRow("Watched media", seconds(snapshot.network.durationWatched))
            diagnosticsRow("Latest-period startup time", seconds(snapshot.network.startupTime))
            diagnosticsRow("Stalls", integer(snapshot.network.numberOfStalls))
            diagnosticsRow("Overdue downloads", integer(snapshot.network.overdueDownloadCount))
            diagnosticsRow("Dropped video frames", integer(snapshot.network.droppedVideoFrameCount))
            diagnosticsRow(
                "Server-address changes",
                integer(snapshot.network.serverAddressChangeCount)
            )
            diagnosticsRow("Error-log entries", "\(snapshot.errorLogEventCount)")

            if let slowDelivery = snapshot.monitor?.slowDelivery {
                diagnosticsRow("Slow segment requests", "\(slowDelivery.totalCount)")
                diagnosticsRow(
                    "Slow-request audio / video / muxed / unknown",
                    "\(slowDelivery.audioCount) / \(slowDelivery.videoCount) / " +
                    "\(slowDelivery.muxedCount) / \(slowDelivery.unknownCount)"
                )
                diagnosticsRow(
                    "Worst request / segment-duration ratio",
                    ratio(slowDelivery.worstRatio)
                )
                diagnosticsRow("Worst audio ratio", ratio(slowDelivery.worstAudioRatio))
                diagnosticsRow("Worst video ratio", ratio(slowDelivery.worstVideoRatio))
                diagnosticsRow("Worst muxed ratio", ratio(slowDelivery.worstMuxedRatio))
                diagnosticsRow("Worst unknown ratio", ratio(slowDelivery.worstUnknownRatio))
                diagnosticsTimestampRow(
                    "Latest slow request",
                    slowDelivery.latestOccurredAt,
                    missing: "None"
                )
                diagnosticsRow(
                    "Latest slow media",
                    slowDelivery.latestMediaType.map(friendlyMediaType) ?? "Unknown"
                )
            }
        }
    }

    private var requestTraceDetails: some View {
        Group {
            if let trace = snapshot.monitor?.requestTrace {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        "Latest \(trace.entries.count) of \(trace.receivedCount) completed typed requests. " +
                        "\(trace.droppedCount) older request\(trace.droppedCount == 1 ? "" : "s") evicted. " +
                        "URLs, headers, server addresses, and key identifiers are never retained."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    if trace.entries.isEmpty {
                        emptyState("No typed HLS or content-key request has completed yet.")
                    } else {
                        ForEach(Array(trace.entries.enumerated().reversed()), id: \.offset) { _, entry in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 7) {
                                    Label(
                                        requestKind(entry.kind),
                                        systemImage: entry.didFail
                                            ? "xmark.circle.fill"
                                            : "checkmark.circle.fill"
                                    )
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(entry.didFail ? Color.orange : Color.secondary)

                                    Text(friendlyMediaType(entry.mediaType))
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    timestampText(entry.occurredAt)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Text(
                                    "Total \(seconds(entry.requestDuration)) · TTFB \(seconds(entry.timeToFirstByte)) · " +
                                    "transfer \(seconds(entry.transferDuration))" +
                                    (entry.segmentDeliveryRatio.map { " · \($0.formatted(.number.precision(.fractionLength(2))))× media duration" } ?? "")
                                )
                                .font(.caption)
                                .monospacedDigit()

                                Text(
                                    "HTTP \(integer(entry.httpStatusCode)) · " +
                                    "\(entry.mimeCategory.map(friendlyMIMECategory) ?? "Unknown MIME") · " +
                                    "\(entry.networkProtocol ?? "Unknown protocol") · " +
                                    "\(entry.fetchType.map(friendlyFetchType) ?? "Unknown fetch")"
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                                Text(
                                    "Received \(bytes(entry.responseBodyBytes)) · decoded \(bytes(entry.decodedBodyBytes)) · " +
                                    requestFlags(entry)
                                )
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            }
                            .padding(10)
                            .background(
                                .quaternary.opacity(0.65),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            } else {
                emptyState("Typed request trace is unavailable for this playback path.")
            }
        }
    }

    private var tracksDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            trackList("Audio", tracks: snapshot.audioTracks)
            Divider()
            trackList("Subtitles", tracks: snapshot.subtitleTracks)
        }
    }

    private var classifierDetails: some View {
        diagnosticsRows {
            if let monitor = snapshot.monitor {
                diagnosticsRow("Candidates", "\(monitor.classifier.candidateCount)")
                diagnosticsRow("Emitted", "\(monitor.classifier.emittedCount)")
                diagnosticsRow("Suppressed", "\(monitor.classifier.suppressedCount)")
                diagnosticsRow(
                    "Calibration sample cap",
                    "\(monitor.classifier.sampleCap)" +
                    (monitor.classifier.sampleCapReached ? " · reached" : " · not reached")
                )
            } else {
                diagnosticsRow("Classifier", "Unavailable")
            }

            diagnosticsRow("History received", "\(snapshot.history.receivedCount)")
            diagnosticsRow("History retained", "\(snapshot.history.retainedCount)")
            diagnosticsRow("History dropped", "\(snapshot.history.droppedCount)")
            diagnosticsRow("History cleared", "\(snapshot.history.clearedCount)")
            diagnosticsRow("Captured incidents", "\(snapshot.incidents.count) / 20")
            if let trace = snapshot.monitor?.requestTrace {
                diagnosticsRow(
                    "Request trace retained / received / dropped",
                    "\(trace.entries.count) / \(trace.receivedCount) / \(trace.droppedCount)"
                )
            }
        }
    }

    private func diagnosticsSection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            Divider()

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private func diagnosticsRows<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            content()
        }
    }

    private func diagnosticsRow(
        _ title: String,
        _ value: String,
        accessibilityValue: String? = nil
    ) -> some View {
        LabeledContent {
            Text(value)
                .monospacedDigit()
                .textSelection(.enabled)
                .frame(maxWidth: 380, alignment: .leading)
        } label: {
            Text(title)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue ?? value)
    }

    private func diagnosticsTimestampRow(
        _ title: String,
        _ date: Date?,
        missing: String = "Unknown"
    ) -> some View {
        let displayValue = date.map(shortTimestamp) ?? missing
        let fullValue = date.map(fullTimestamp) ?? missing
        return diagnosticsRow(title, displayValue, accessibilityValue: fullValue)
            .help(fullValue)
    }

    private func timestampText(_ date: Date) -> some View {
        let fullValue = fullTimestamp(date)
        return Text(shortTimestamp(date))
            .monospacedDigit()
            .textSelection(.enabled)
            .help(fullValue)
            .accessibilityLabel(fullValue)
    }

    private func issueCard(_ issue: PlaybackDiagnosticsIssue) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon(for: issue.level))
                .foregroundStyle(color(for: issue.level))
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(scopeLabel(issue.scope).uppercased())
                    Text(levelLabel(issue.level).uppercased())
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(color(for: issue.level))

                Text(issue.title)
                    .font(.callout.weight(.semibold))

                Text(issue.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let recommendation = recommendationText(issue.recommendation) {
                    Text("Try this: \(recommendation)")
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .background(color(for: issue.level).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(color(for: issue.level).opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func trackList(_ title: String, tracks: [PlaybackDiagnosticsTrack]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title) · \(tracks.count)")
                .font(.caption.weight(.semibold))

            if tracks.isEmpty {
                emptyState("No \(title.lowercased()) track is exposed.")
            } else {
                ForEach(trackRows(tracks)) { row in
                    HStack(spacing: 7) {
                        Image(systemName: row.track.isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(row.track.isSelected ? Color.accentColor : Color.secondary)
                            .accessibilityHidden(true)
                        Text(row.track.name)
                        if let languageCode = row.track.languageCode {
                            Text(languageCode)
                                .foregroundStyle(.secondary)
                        }
                        if let identifier = row.track.identifier {
                            Text(identifier)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                                .accessibilityHidden(true)
                        }
                    }
                    .font(.caption)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(row.track.isSelected ? "Selected" : "Not selected")
                }
            }
        }
    }

    private func emptyState(_ text: String) -> some View {
        Label(text, systemImage: "minus.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func pageBadgeCount(_ page: PlaybackDiagnosticsPage) -> Int? {
        switch page {
        case .overview:
            return activeIssues.count
        case .events:
            return snapshot.incidents.count
                + snapshot.recentHealthEvents.count
                + snapshot.recentErrors.count
        case .technical:
            return nil
        }
    }

    private func pageAccessibilityValue(_ page: PlaybackDiagnosticsPage) -> String {
        guard let count = pageBadgeCount(page), count > 0 else {
            return page.subtitle
        }
        return "\(page.subtitle). \(count) item\(count == 1 ? "" : "s")."
    }

    private var canCaptureIncident: Bool {
        switch snapshot.session.availability {
        case .noPlayerItem, .unsupportedBackend:
            return false
        case .startingAVMetrics,
             .activeAVMetrics,
             .failedAVMetrics,
             .endedAVMetrics,
             .activeErrorLogFallback,
             .monitoringDisabled,
             .monitorNotAttached:
            return true
        }
    }

    private var allIssues: [PlaybackDiagnosticsIssue] {
        snapshot.issues()
    }

    private var activeIssues: [PlaybackDiagnosticsIssue] {
        allIssues.filter { $0.scope == .active }
    }

    private var historicalIssues: [PlaybackDiagnosticsIssue] {
        allIssues.filter { $0.scope == .historical }
    }

    private var coverageIssues: [PlaybackDiagnosticsIssue] {
        allIssues.filter { $0.scope == .coverage }
    }

    private var currentPresentationStatus: PlaybackDiagnosticsCurrentStatus {
        PlaybackDiagnosticsCurrentStatus.resolve(
            availability: snapshot.session.availability,
            itemStatus: snapshot.playback.itemStatus,
            timeControlStatus: snapshot.playback.timeControlStatus,
            highestActiveIssue: activeIssues.map(\.level).max()
        )
    }

    private var currentStatusIcon: String {
        switch currentPresentationStatus {
        case .noProblemDetected:
            return "checkmark.circle.fill"
        case let .needsAttention(level):
            return icon(for: level)
        case .waiting:
            return "hourglass.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .nothingPlaying:
            return "play.slash"
        case .checkLimited:
            return "exclamationmark.circle.fill"
        case .detailsUnavailable:
            return "questionmark.circle"
        }
    }

    private var currentStatusColor: Color {
        switch currentPresentationStatus {
        case .noProblemDetected:
            return .green
        case let .needsAttention(level):
            return color(for: level)
        case .waiting:
            return .orange
        case .failed:
            return .red
        case .nothingPlaying:
            return .secondary
        case .checkLimited:
            return .orange
        case .detailsUnavailable:
            return .secondary
        }
    }

    private var currentStatusDetail: String {
        switch currentPresentationStatus {
        case .noProblemDetected:
            return "No active issue is visible in this sample. Some media defects cannot be detected automatically."
        case .needsAttention:
            return activeIssues.first?.title
                ?? "The current sample contains a playback signal that may need attention."
        case .waiting:
            return snapshot.playback.waitingReason
                ?? "The player is waiting for enough media to continue."
        case .failed:
            return "The current player item stopped with an error."
        case .nothingPlaying:
            return "Start a video to see playback status and connection details."
        case .checkLimited:
            return "Only part of this playback session can be checked right now. Open Monitoring for details."
        case .detailsUnavailable:
            return "This player does not expose the detailed playback information used by this check."
        }
    }

    private var statusSymbol: some View {
        Image(systemName: currentStatusIcon)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(currentStatusColor)
            .frame(width: 42, height: 42)
            .background(currentStatusColor.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }

    private var coverageStatusLevel: PlaybackDiagnosticsLevel {
        coverageIssues.map(\.level).max() ?? .observation
    }

    private var coverageStatusColor: Color {
        coverageIssues.isEmpty ? .secondary : color(for: coverageStatusLevel)
    }

    private var monitoringStatusTitle: String {
        switch snapshot.session.availability {
        case .activeAVMetrics:
            return "Full monitoring"
        case .startingAVMetrics:
            return "Starting monitoring"
        case .activeErrorLogFallback:
            return "Basic monitoring"
        case .failedAVMetrics, .endedAVMetrics:
            return "Limited monitoring"
        case .monitoringDisabled:
            return "Monitoring is off"
        case .monitorNotAttached:
            return "Monitoring unavailable"
        case .noPlayerItem:
            return "Waiting for playback"
        case .unsupportedBackend:
            return "Monitoring unsupported"
        }
    }

    private var monitoringStatusIcon: String {
        switch snapshot.session.availability {
        case .activeAVMetrics:
            return "checkmark.circle.fill"
        case .startingAVMetrics:
            return "clock"
        case .activeErrorLogFallback, .failedAVMetrics, .endedAVMetrics:
            return "exclamationmark.circle.fill"
        case .monitoringDisabled, .monitorNotAttached, .noPlayerItem, .unsupportedBackend:
            return "minus.circle.fill"
        }
    }

    private var coverageLimitationText: String {
        let count = coverageIssues.count
        guard count > 0 else {
            return "No observer degradation · passive limits apply"
        }
        return "\(count) coverage limitation\(count == 1 ? "" : "s") · " +
            "highest \(levelLabel(coverageStatusLevel).lowercased())"
    }

    private var hlsEvidenceText: String {
        switch snapshot.playback.isLikelyHLS {
        case true:
            return "HLS confirmed"
        case false:
            return "HLS not identified"
        case nil:
            return "HLS evidence pending"
        }
    }

    private var assetIdentifierAccessibilityValue: String {
        guard let identifier = snapshot.session.assetIdentifier else {
            return "Missing"
        }
        if identifier.hasPrefix("sha256:") {
            return "Asset fingerprint available"
        }
        return "Numeric asset ID \(identifier)"
    }

    private var contentTitle: String {
        sampledContentTitle
    }

    private static func contentTitle(from playerManager: PlayerManager) -> String {
        guard let title = playerManager.playerItem?.title.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return "Current player item"
        }
        return title
    }

    private var sessionEvidenceHeadline: String {
        let findingCount = historicalIssues.count
        let incidentCount = snapshot.incidents.count
        if findingCount == 0, incidentCount == 0 {
            return "No retained session finding"
        }
        var parts: [String] = []
        if findingCount > 0 {
            parts.append("\(findingCount) session finding\(findingCount == 1 ? "" : "s")")
        }
        if incidentCount > 0 {
            parts.append("\(incidentCount) saved moment\(incidentCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    private var sampleStateText: String {
        if isLive {
            return sampleAgeSeconds < 2
                ? "Auto-updating · just now"
                : "Auto-updating · sample \(sampleAgeSeconds) seconds old"
        }
        return "Auto-update paused · captured \(shortTimestamp(snapshot.session.capturedAt))"
    }

    private var sampleStateAccessibilityText: String {
        guard !isLive else { return sampleStateText }
        return "Auto-update paused. Captured \(fullTimestamp(snapshot.session.capturedAt))"
    }

    private var sampleAgeSeconds: Int {
        max(Int(displayTime.timeIntervalSince(snapshot.session.capturedAt).rounded(.down)), 0)
    }

    private var friendlyPlaybackState: String {
        friendlyTimeControlStatus(snapshot.playback.timeControlStatus)
    }

    private var throughputMargin: String {
        guard let observed = snapshot.network.observedBitRate,
              let indicated = snapshot.network.indicatedBitRate,
              observed.isFinite,
              indicated.isFinite,
              indicated > 0 else {
            return "Unknown"
        }
        return String(format: "%.1f× demand", observed / indicated)
    }

    private var bufferMetricDetail: String {
        let keepUp = snapshot.playback.isPlaybackLikelyToKeepUp
            ? "Expected to keep up"
            : "Keep-up uncertain"
        guard let postStartWaitCount = snapshot.monitor?.waiting.postStartWaitCount else {
            return keepUp
        }
        return "\(keepUp) · \(postStartWaitCount) post-start wait" +
            "\(postStartWaitCount == 1 ? "" : "s")"
    }

    private var requestTraceTitle: String {
        guard let trace = snapshot.monitor?.requestTrace else {
            return "Recent Requests"
        }
        return "Recent Requests · \(trace.entries.count) of \(trace.receivedCount)"
    }

    private var liveBinding: Binding<Bool> {
        Binding(
            get: { isLive },
            set: { newValue in
                isLive = newValue
                if newValue {
                    refresh()
                }
            }
        )
    }

    private var errorRows: [DiagnosticsErrorRow] {
        var occurrences: [String: Int] = [:]
        return snapshot.recentErrors.map { error in
            let base = [
                error.occurredAt.map { String($0.timeIntervalSinceReferenceDate) } ?? "item",
                error.domain ?? "unlisted",
                String(error.code)
            ]
            .joined(separator: "|")
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            return DiagnosticsErrorRow(id: "\(base)|\(occurrence)", error: error)
        }
    }

    private var healthEventRows: [DiagnosticsHealthEventRow] {
        let retainedOffset = snapshot.history.droppedCount + snapshot.history.clearedCount
        return snapshot.recentHealthEvents.enumerated().map { index, event in
            DiagnosticsHealthEventRow(
                id: DiagnosticsHealthEventRow.ID(
                    event: event,
                    occurrence: retainedOffset + index
                ),
                event: event
            )
        }
    }

    private func trackRows(_ tracks: [PlaybackDiagnosticsTrack]) -> [DiagnosticsTrackRow] {
        var occurrences: [String: Int] = [:]
        return tracks.map { track in
            let base = track.identifier ?? "\(track.name)|\(track.languageCode ?? "none")"
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            return DiagnosticsTrackRow(id: "\(base)|\(occurrence)", track: track)
        }
    }

    private var signalPath: String {
        switch snapshot.session.availability {
        case .startingAVMetrics:
            return "Starting HLS request metrics"
        case .activeAVMetrics:
            return "HLS request metrics + stalls"
        case .failedAVMetrics:
            return "HLS request metrics failed"
        case .endedAVMetrics:
            return "HLS request metrics ended"
        case .activeErrorLogFallback:
            return "Error-log entries + stalls"
        default:
            return "Inactive"
        }
    }

    private func friendlyItemStatus(_ status: String) -> String {
        switch status {
        case "ready":
            return "Ready"
        case "failed":
            return "Failed"
        case "unavailable":
            return "Unavailable"
        default:
            return "Preparing"
        }
    }

    private func friendlyTimeControlStatus(_ status: String) -> String {
        switch status {
        case "playing":
            return "Playing"
        case "waiting":
            return "Waiting"
        case "paused":
            return "Paused"
        case "unavailable":
            return "Unavailable"
        default:
            return status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func friendlySignal(_ signal: PlaybackHealthSignalKind) -> String {
        switch signal {
        case .playlistRequestFailure:
            return "Playlist request failed"
        case .mediaSegmentRequestFailure:
            return "Media segment request failed"
        case .contentKeyRequestFailure:
            return "Content-key request failed"
        case .errorLogEntry:
            return "AVFoundation error recorded"
        case .playbackStall:
            return "Playback stalled"
        }
    }

    private func friendlyMediaType(_ mediaType: PlaybackHealthMediaType) -> String {
        switch mediaType {
        case .audio:
            return "Audio"
        case .video:
            return "Video"
        case .muxed:
            return "Muxed audio and video"
        case .unknown:
            return "Unattributed media"
        }
    }

    private func friendlyWaitKind(_ kind: PlaybackHealthWaitKind) -> String {
        switch kind {
        case .initial:
            return "Initial startup"
        case .postStart:
            return "Post-start"
        case .seek:
            return "Seek"
        }
    }

    private func requestKind(_ kind: PlaybackHealthRequestKind) -> String {
        switch kind {
        case .playlist:
            return "Playlist"
        case .segment:
            return "Media segment"
        case .contentKey:
            return "Content key"
        }
    }

    private func friendlyMIMECategory(_ category: PlaybackHealthMIMECategory) -> String {
        switch category {
        case .hlsPlaylist:
            return "HLS playlist"
        case .transportStream:
            return "MPEG transport stream"
        case .mp4:
            return "MP4 media"
        case .html:
            return "HTML"
        case .json:
            return "JSON"
        case .text:
            return "Plain text"
        case .binary:
            return "Binary"
        case .other:
            return "Other MIME"
        }
    }

    private func friendlyFetchType(_ type: PlaybackHealthResourceFetchType) -> String {
        switch type {
        case .unknown:
            return "Unknown fetch"
        case .networkLoad:
            return "Network"
        case .serverPush:
            return "Server push"
        case .localCache:
            return "Local cache"
        }
    }

    private func requestTiming(_ timing: PlaybackHealthRequestTimingAggregate) -> String {
        let total = timing.summedRequestDuration.map(seconds) ?? "Unknown time"
        return "\(timing.requestCount) request\(timing.requestCount == 1 ? "" : "s") · " +
            "\(total) across \(timing.durationSampleCount) timed"
    }

    private func requestFlags(_ entry: PlaybackHealthRequestTraceEntry) -> String {
        var flags = [
            "cache \(optionalYesNo(entry.wasReadFromCache).lowercased())",
            "reused \(optionalYesNo(entry.reusedConnection).lowercased())"
        ]
        if entry.proxyConnection == true {
            flags.append("proxy")
        }
        if entry.constrainedNetwork == true {
            flags.append("constrained")
        }
        if entry.expensiveNetwork == true {
            flags.append("expensive")
        }
        if entry.cellularNetwork == true {
            flags.append("cellular")
        }
        if entry.multipathConnection == true {
            flags.append("multipath")
        }
        if let didRecover = entry.didRecover {
            flags.append(didRecover ? "recovered" : "not recovered")
        }
        return flags.joined(separator: " · ")
    }

    private func friendlyConfidence(_ confidence: PlaybackHealthConfidence) -> String {
        switch confidence {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }

    private func friendlyRecovery(_ recovered: Bool?) -> String {
        switch recovered {
        case true:
            return "request recovered"
        case false:
            return "request did not recover"
        case nil:
            return "recovery unknown"
        }
    }

    private func friendlyStreamState(_ state: PlaybackHealthMonitorStreamState) -> String {
        switch state {
        case .starting:
            return "Starting"
        case .observing:
            return "Observing with AVMetrics"
        case .fallbackObserving:
            return "Observing with error-log fallback"
        case .failed:
            return "Failed"
        case .ended:
            return "Ended"
        }
    }

    private func friendlyFallbackReason(_ reason: PlaybackHealthFallbackReason) -> String {
        switch reason {
        case .legacyOS:
            return "macOS 14 error-log fallback"
        case .metricsFailed:
            return "AVMetrics failed"
        case .metricsEnded:
            return "AVMetrics ended"
        }
    }

    private func variantDescription(_ variant: PlaybackHealthVariant?) -> String {
        guard let variant else { return "Unknown" }
        let resolution = variant.resolution ?? "unknown resolution"
        let peak = variant.peakBitRate.map { bitRate($0) } ?? "unknown peak"
        let average = variant.averageBitRate.map { bitRate($0) } ?? "unknown average"
        let frameRate = variant.frameRate.map { frequency($0) } ?? "unknown frame rate"
        return "\(resolution) · peak \(peak) · average \(average) · \(frameRate)"
    }

    private func scopeLabel(_ scope: PlaybackDiagnosticsIssueScope) -> String {
        switch scope {
        case .active:
            return "Active"
        case .historical:
            return "Session"
        case .coverage:
            return "Coverage"
        }
    }

    private func levelLabel(_ level: PlaybackDiagnosticsLevel) -> String {
        switch level {
        case .observation:
            return "Observation"
        case .notice:
            return "Notice"
        case .warning:
            return "Warning"
        case .critical:
            return "Critical"
        }
    }

    private func icon(for level: PlaybackDiagnosticsLevel) -> String {
        switch level {
        case .observation:
            return "info.circle"
        case .notice:
            return "exclamationmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .critical:
            return "xmark.octagon"
        }
    }

    private func color(for level: PlaybackDiagnosticsLevel) -> Color {
        switch level {
        case .observation:
            return .secondary
        case .notice:
            return .blue
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    private func color(for confidence: PlaybackHealthConfidence) -> Color {
        switch confidence {
        case .low:
            return .secondary
        case .medium:
            return .blue
        case .high:
            return .orange
        }
    }

    private func recommendationText(_ recommendation: String?) -> String? {
        guard let recommendation else { return nil }
        let trimmed = recommendation.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func captureIncident() {
        let feedback: DiagnosticsCaptureFeedback
        if let incident = playerManager.capturePlaybackDiagnosticsIncident() {
            feedback = DiagnosticsCaptureFeedback(
                message: "Moment saved · ID \(String(incident.id.uuidString.prefix(8)))",
                succeeded: true
            )
            playbackDiagnosticsLogger.info("diagnostics dashboard captured incident")
        } else {
            feedback = DiagnosticsCaptureFeedback(
                message: "Couldn’t save · no active video",
                succeeded: false
            )
            playbackDiagnosticsLogger.error("diagnostics dashboard incident capture unavailable")
        }

        captureFeedback = feedback
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: feedback.message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if captureFeedback?.id == feedback.id {
                captureFeedback = nil
            }
        }
    }

    private func refresh() {
        snapshot = playerManager.fetchPlaybackDiagnostics()
        sampledContentTitle = Self.contentTitle(from: playerManager)
        displayTime = Date()
    }

    private func copyReport() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.writeObjects([snapshot.report() as NSString]) else {
            didCopy = false
            let feedback = DiagnosticsCaptureFeedback(
                message: "Couldn’t copy support report",
                succeeded: false
            )
            captureFeedback = feedback
            NSAccessibility.post(
                element: NSApplication.shared,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: feedback.message,
                    .priority: NSAccessibilityPriorityLevel.high.rawValue
                ]
            )
            playbackDiagnosticsLogger.error("diagnostics dashboard could not write sanitized report")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if captureFeedback?.id == feedback.id {
                    captureFeedback = nil
                }
            }
            return
        }
        playbackDiagnosticsLogger.info("diagnostics dashboard copied sanitized report")
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            didCopy = false
        }
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    private func optionalYesNo(_ value: Bool?) -> String {
        value.map(yesNo) ?? "Unknown"
    }

    private func integer(_ value: Int?) -> String {
        value.map(String.init) ?? "Unknown"
    }

    private func seconds(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "Unknown" }
        return String(format: "%.2f s", value)
    }

    private func time(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "Unknown" }
        let total = Int(value.rounded(.down))
        return String(
            format: "%02d:%02d:%02d",
            total / 3600,
            (total / 60) % 60,
            total % 60
        )
    }

    private func shortTimestamp(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle()
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .second(.twoDigits)
                .secondFraction(.fractional(3))
                .locale(Locale(identifier: "en_GB_POSIX"))
        )
    }

    private func fullTimestamp(_ date: Date) -> String {
        date.formatted(
            Date.ISO8601FormatStyle(
                includingFractionalSeconds: true,
                timeZone: .gmt
            )
        )
    }

    private func frequency(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "Unknown" }
        return String(format: "%.2f fps", value)
    }

    private func bitRate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "Unknown" }
        return String(format: "%.2f Mbps", value / 1_000_000)
    }

    private func ratio(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "Unknown" }
        return String(format: "%.2f×", value)
    }

    private func bytes(_ value: Int64?) -> String {
        guard let value else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
#endif
