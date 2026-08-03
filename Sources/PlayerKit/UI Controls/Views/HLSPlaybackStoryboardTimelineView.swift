#if os(macOS)
import Charts
import SwiftUI

struct HLSPlaybackStoryboardTimelineView: View {
    let storyboard: PlaybackDiagnosticsStoryboard
    let displayTime: Date
    @Binding var zoomSeconds: TimeInterval
    @Binding var selectedIncidentID: UUID?
    @State private var selectedDate: Date?

    var body: some View {
        // ponytail: Build one bounded window per render. If diagnostics grows beyond
        // the retained session cap, move this projection into the recorder.
        let window = TimelineWindow(
            storyboard: storyboard,
            displayTime: displayTime,
            zoomSeconds: zoomSeconds
        )

        VStack(spacing: 0) {
            timelineHeader

            VStack(spacing: 0) {
                lane(title: "Playback", subtitle: "State · buffer") {
                    playbackChart(window)
                }

                lane(title: "Delivery", subtitle: "Observed · indicated") {
                    deliveryChart(window)
                }

                lane(title: "Rendition", subtitle: "Quality · events") {
                    renditionChart(window)
                }
            }
            .background(PlaybackDiagnosticsTheme.recessed)

            timeFooter(window)
        }
        .onChange(of: selectedDate) { _, date in
            guard let date else { return }
            if let selectedIncidentID,
               storyboard.incidents.first(where: {
                   $0.id == selectedIncidentID
               })?.startedAt == date {
                return
            }
            selectIncident(at: date, visibleEnd: window.end)
        }
        .onChange(of: selectedIncidentID) { _, incidentID in
            syncSelectedDate(to: incidentID)
        }
        .onAppear {
            syncSelectedDate(to: selectedIncidentID)
        }
        .accessibilityIdentifier("player.diagnostics.storyboard.timeline")
    }

    private var timelineHeader: some View {
        HStack(spacing: 10) {
            Text("SESSION TIMELINE")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)

            legend("Buffer", color: PlaybackDiagnosticsTheme.green)
            legend("Observed", color: Color.cyan)
            legend("Indicated", color: Color.blue)
            legend("Incident", color: PlaybackDiagnosticsTheme.warning)

            Spacer()

            Button {
                zoomSeconds = max(60, zoomSeconds / 2)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("Zoom in")
            .accessibilityLabel("Zoom timeline in")
            .disabled(zoomSeconds <= 60)

            Button {
                zoomSeconds = min(300, zoomSeconds * 2)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("Zoom out")
            .accessibilityLabel("Zoom timeline out")
            .disabled(zoomSeconds >= 300)

            Button("Reset Zoom") {
                zoomSeconds = 300
            }
            .buttonStyle(.borderless)
            .font(.caption2.weight(.medium))
            .disabled(zoomSeconds == 300)
        }
        .foregroundStyle(PlaybackDiagnosticsTheme.secondary)
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(PlaybackDiagnosticsTheme.elevated)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PlaybackDiagnosticsTheme.divider)
                .frame(height: 1)
        }
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 9, height: 2)
            Text(title)
                .font(.caption2)
                .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private func lane<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(PlaybackDiagnosticsTheme.secondary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
                    .lineLimit(1)
            }
            .padding(.leading, 9)
            .frame(width: 82, alignment: .leading)
            .accessibilityElement(children: .combine)

            Rectangle()
                .fill(PlaybackDiagnosticsTheme.divider)
                .frame(width: 1)

            content()
                .padding(.horizontal, 6)
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PlaybackDiagnosticsTheme.divider.opacity(0.65))
                .frame(height: 1)
        }
    }

    private func playbackChart(_ window: TimelineWindow) -> some View {
        Chart {
            incidentBands(window.incidents, visibleStart: window.start, visibleEnd: window.end, maxY: window.bufferScaleMaximum)

            ForEach(window.samples) { sample in
                RectangleMark(
                    xStart: .value("State start", sample.capturedAt.addingTimeInterval(-0.5)),
                    xEnd: .value("State end", sample.capturedAt.addingTimeInterval(0.5)),
                    yStart: .value("State minimum", 0),
                    yEnd: .value("State maximum", window.bufferScaleMaximum)
                )
                .foregroundStyle(stateColor(sample.state).opacity(0.10))
            }

            ForEach(window.samples) { sample in
                if let buffer = sample.bufferHeadroom {
                    LineMark(
                        x: .value("Time", sample.capturedAt),
                        y: .value("Buffer seconds", buffer)
                    )
                    .foregroundStyle(PlaybackDiagnosticsTheme.green)
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
                    .interpolationMethod(.linear)
                }
            }

            ForEach(window.waitingSamples) { sample in
                PointMark(
                    x: .value("Wait time", sample.capturedAt),
                    y: .value("Wait buffer", sample.bufferHeadroom ?? 0)
                )
                .foregroundStyle(PlaybackDiagnosticsTheme.warning)
                .symbolSize(20)
            }

            recoveryBoundaries(window.recoveryBoundaries, maxY: window.bufferScaleMaximum)
            nowCursor(window.now, maxY: window.bufferScaleMaximum)
        }
        .chartXScale(domain: window.start ... window.end)
        .chartYScale(domain: 0 ... window.bufferScaleMaximum)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                AxisGridLine()
                    .foregroundStyle(PlaybackDiagnosticsTheme.divider)
                AxisValueLabel()
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
            }
        }
        .chartXSelection(value: $selectedDate)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback state and buffer lane")
        .accessibilityValue(playbackAccessibilityValue(window))
    }

    private func deliveryChart(_ window: TimelineWindow) -> some View {
        Chart {
            incidentBands(window.incidents, visibleStart: window.start, visibleEnd: window.end, maxY: window.deliveryScaleMaximum)
            deliveryLines(window.samples)
            deliveryEvidenceMarks(window.deliveryEvidence, scaleMaximum: window.deliveryScaleMaximum)
            recoveryBoundaries(window.recoveryBoundaries, maxY: window.deliveryScaleMaximum)
            nowCursor(window.now, maxY: window.deliveryScaleMaximum)
        }
        .chartXScale(domain: window.start ... window.end)
        .chartYScale(domain: 0 ... window.deliveryScaleMaximum)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(PlaybackDiagnosticsTheme.divider)
                AxisValueLabel {
                    if let rate = value.as(Double.self) {
                        Text(axisBitRate(rate))
                    }
                }
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
            }
        }
        .chartXSelection(value: $selectedDate)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Observed versus indicated delivery lane")
        .accessibilityValue(deliveryAccessibilityValue(window))
    }

    private func renditionChart(_ window: TimelineWindow) -> some View {
        Chart {
            incidentBands(window.incidents, visibleStart: window.start, visibleEnd: window.end, maxY: window.renditionScaleMaximum)
            renditionLines(window.renditionSamples)
            renditionEvidenceMarks(window.renditionEvidence, scaleMaximum: window.renditionScaleMaximum)
            bookmarkMarks(window.bookmarks)
            recoveryBoundaries(window.recoveryBoundaries, maxY: window.renditionScaleMaximum)
            nowCursor(window.now, maxY: window.renditionScaleMaximum)
        }
        .chartXScale(domain: window.start ... window.end)
        .chartYScale(domain: 0 ... window.renditionScaleMaximum)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) {
                AxisGridLine()
                    .foregroundStyle(PlaybackDiagnosticsTheme.divider)
                AxisTick()
                    .foregroundStyle(PlaybackDiagnosticsTheme.divider)
                AxisValueLabel(format: .dateTime.minute().second())
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(PlaybackDiagnosticsTheme.divider)
                AxisValueLabel {
                    if let height = value.as(Double.self) {
                        Text("\(Int(height))p")
                    }
                }
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
            }
        }
        .chartXSelection(value: $selectedDate)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rendition and high-signal event lane")
        .accessibilityValue(renditionAccessibilityValue(window))
    }

    @ChartContentBuilder
    private func deliveryLines(_ samples: [PlaybackDiagnosticsSample]) -> some ChartContent {
        ForEach(samples) { sample in
            if let observed = sample.observedBitRate {
                LineMark(
                    x: .value("Time", sample.capturedAt),
                    y: .value("Observed delivery", observed)
                )
                .foregroundStyle(Color.cyan)
                .lineStyle(StrokeStyle(lineWidth: 1.4))
                .interpolationMethod(.linear)
            }
            if let indicated = sample.indicatedBitRate {
                LineMark(
                    x: .value("Time", sample.capturedAt),
                    y: .value("Indicated bitrate", indicated)
                )
                .foregroundStyle(Color.blue)
                .lineStyle(StrokeStyle(lineWidth: 1.1, dash: [4, 3]))
                .interpolationMethod(.linear)
            }
        }
    }

    @ChartContentBuilder
    private func deliveryEvidenceMarks(
        _ evidence: [PlaybackDiagnosticsEvidence],
        scaleMaximum: Double
    ) -> some ChartContent {
        ForEach(evidence) { evidence in
            PointMark(
                x: .value("Evidence time", evidence.occurredAt),
                y: .value("Evidence", scaleMaximum * 0.08)
            )
            .foregroundStyle(
                PlaybackDiagnosticsTheme.color(for: evidence.level)
            )
            .symbolSize(evidence.level >= .warning ? 32 : 18)
        }
    }

    @ChartContentBuilder
    private func renditionLines(_ samples: [RenditionSample]) -> some ChartContent {
        ForEach(samples) { sample in
            LineMark(
                x: .value("Time", sample.capturedAt),
                y: .value("Rendition height", sample.height)
            )
            .foregroundStyle(Color.blue)
            .lineStyle(StrokeStyle(lineWidth: 2.2))
            .interpolationMethod(.stepEnd)
        }
    }

    @ChartContentBuilder
    private func renditionEvidenceMarks(
        _ evidence: [PlaybackDiagnosticsEvidence],
        scaleMaximum: Double
    ) -> some ChartContent {
        ForEach(evidence) { evidence in
            RuleMark(x: .value("Event time", evidence.occurredAt))
                .foregroundStyle(
                    PlaybackDiagnosticsTheme.color(for: evidence.level).opacity(0.7)
                )
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))

            PointMark(
                x: .value("Event time", evidence.occurredAt),
                y: .value("Event", scaleMaximum * 0.12)
            )
            .foregroundStyle(
                PlaybackDiagnosticsTheme.color(for: evidence.level)
            )
            .symbolSize(evidence.level >= .warning ? 36 : 20)
        }
    }

    @ChartContentBuilder
    private func bookmarkMarks(_ bookmarks: [PlaybackDiagnosticsBookmark]) -> some ChartContent {
        ForEach(bookmarks) { bookmark in
            RuleMark(x: .value("Bookmark", bookmark.capturedAt))
                .foregroundStyle(PlaybackDiagnosticsTheme.primary.opacity(0.65))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: .center) {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2)
                        .foregroundStyle(PlaybackDiagnosticsTheme.primary)
                        .accessibilityLabel("Saved moment")
                }
        }
    }

    @ChartContentBuilder
    private func incidentBands(
        _ incidents: [PlaybackDiagnosticsAutomaticIncident],
        visibleStart: Date,
        visibleEnd: Date,
        maxY: Double
    ) -> some ChartContent {
        ForEach(incidents) { incident in
            RectangleMark(
                xStart: .value("Incident start", max(incident.startedAt, visibleStart)),
                xEnd: .value(
                    "Incident end",
                    min(incident.endedAt ?? visibleEnd, visibleEnd)
                ),
                yStart: .value("Incident minimum", 0),
                yEnd: .value("Incident maximum", maxY)
            )
            .foregroundStyle(
                PlaybackDiagnosticsTheme.color(for: incident.severity)
                    .opacity(incident.id == selectedIncidentID ? 0.22 : 0.10)
            )
        }
    }

    @ChartContentBuilder
    private func recoveryBoundaries(
        _ boundaries: [RecoveryBoundary],
        maxY: Double
    ) -> some ChartContent {
        ForEach(boundaries) { boundary in
            RuleMark(x: .value("Recovery", boundary.endedAt))
                .foregroundStyle(PlaybackDiagnosticsTheme.green.opacity(0.65))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
        }
    }

    @ChartContentBuilder
    private func nowCursor(_ now: Date, maxY: Double) -> some ChartContent {
        RuleMark(x: .value("Now", now))
            .foregroundStyle(PlaybackDiagnosticsTheme.green.opacity(0.85))
            .lineStyle(StrokeStyle(lineWidth: 1))
            .annotation(position: .top, alignment: .trailing) {
                Text("NOW")
                    .font(.caption2.bold())
                    .foregroundStyle(PlaybackDiagnosticsTheme.green)
            }
    }

    private func timeFooter(_ window: TimelineWindow) -> some View {
        HStack {
            Text(PlaybackDiagnosticsFormat.shortTime(window.start))
            Spacer()
            Text("\(Int(zoomSeconds)) s window")
            Spacer()
            Text(PlaybackDiagnosticsFormat.shortTime(window.end))
        }
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
        .padding(.horizontal, 92)
        .frame(height: 20)
        .background(PlaybackDiagnosticsTheme.elevated)
        .accessibilityElement(children: .combine)
    }

    private func playbackAccessibilityValue(_ window: TimelineWindow) -> String {
        guard let latest = window.samples.last else { return "No measured samples" }
        return "\(latest.state.rawValue), buffer \(PlaybackDiagnosticsFormat.seconds(latest.bufferHeadroom))"
    }

    private func deliveryAccessibilityValue(_ window: TimelineWindow) -> String {
        guard let latest = window.samples.last else { return "No measured samples" }
        return "Observed \(PlaybackDiagnosticsFormat.bitRate(latest.observedBitRate)), indicated \(PlaybackDiagnosticsFormat.bitRate(latest.indicatedBitRate))"
    }

    private func renditionAccessibilityValue(_ window: TimelineWindow) -> String {
        let latest = window.renditionSamples.last?.resolution ?? "Not measured"
        return "\(latest), \(window.evidenceCount) retained events"
    }

    private func selectIncident(at date: Date, visibleEnd: Date) {
        let containing = storyboard.incidents
            .filter {
                date >= $0.startedAt && date <= ($0.endedAt ?? visibleEnd)
            }
            .max { $0.severity < $1.severity }
        if let containing {
            selectedIncidentID = containing.id
            selectedDate = containing.startedAt
            return
        }
        let nearest = storyboard.incidents.min {
            abs($0.startedAt.timeIntervalSince(date))
                < abs($1.startedAt.timeIntervalSince(date))
        }
        if let nearest,
           abs(nearest.startedAt.timeIntervalSince(date)) <= 5 {
            selectedIncidentID = nearest.id
            selectedDate = nearest.startedAt
        } else {
            selectedIncidentID = nil
            selectedDate = nil
        }
    }

    private func syncSelectedDate(to incidentID: UUID?) {
        guard let incidentID,
              let incident = storyboard.incidents.first(where: {
                  $0.id == incidentID
              }) else {
            selectedDate = nil
            return
        }
        selectedDate = incident.startedAt
    }

    private func stateColor(_ state: PlaybackDiagnosticsSampleState) -> Color {
        switch state {
        case .playing:
            return PlaybackDiagnosticsTheme.green
        case .waiting:
            return PlaybackDiagnosticsTheme.warning
        case .paused:
            return PlaybackDiagnosticsTheme.tertiary
        case .unavailable:
            return PlaybackDiagnosticsTheme.danger
        }
    }

    private func axisBitRate(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        return String(format: "%.0fK", value / 1_000)
    }
}

private struct TimelineWindow {
    let start: Date
    let end: Date
    let now: Date
    let samples: [PlaybackDiagnosticsSample]
    let waitingSamples: [PlaybackDiagnosticsSample]
    let renditionSamples: [RenditionSample]
    let deliveryEvidence: [PlaybackDiagnosticsEvidence]
    let renditionEvidence: [PlaybackDiagnosticsEvidence]
    let evidenceCount: Int
    let bookmarks: [PlaybackDiagnosticsBookmark]
    let incidents: [PlaybackDiagnosticsAutomaticIncident]
    let recoveryBoundaries: [RecoveryBoundary]
    let bufferScaleMaximum: Double
    let deliveryScaleMaximum: Double
    let renditionScaleMaximum: Double

    init(
        storyboard: PlaybackDiagnosticsStoryboard,
        displayTime: Date,
        zoomSeconds: TimeInterval
    ) {
        let end = storyboard.samples.last?.capturedAt ?? displayTime
        let start = end.addingTimeInterval(-zoomSeconds)
        self.start = start
        self.end = end
        self.now = end

        var samples: [PlaybackDiagnosticsSample] = []
        var waitingSamples: [PlaybackDiagnosticsSample] = []
        var renditionSamples: [RenditionSample] = []
        var maximumBuffer = 0.0
        var maximumDelivery = 0.0
        var maximumRendition = 0.0

        for sample in storyboard.samples
        where sample.capturedAt >= start && sample.capturedAt <= end {
            samples.append(sample)
            if sample.state == .waiting {
                waitingSamples.append(sample)
            }
            if let buffer = sample.bufferHeadroom {
                maximumBuffer = max(maximumBuffer, buffer)
            }
            if let observed = sample.observedBitRate {
                maximumDelivery = max(maximumDelivery, observed)
            }
            if let indicated = sample.indicatedBitRate {
                maximumDelivery = max(maximumDelivery, indicated)
            }
            if let height = Self.renditionHeight(sample.resolution) {
                renditionSamples.append(
                    RenditionSample(
                        id: sample.id,
                        capturedAt: sample.capturedAt,
                        height: height,
                        resolution: sample.resolution
                    )
                )
                maximumRendition = max(maximumRendition, height)
            }
        }

        var evidenceCount = 0
        var deliveryEvidence: [PlaybackDiagnosticsEvidence] = []
        var renditionEvidence: [PlaybackDiagnosticsEvidence] = []
        for evidence in storyboard.evidence
        where evidence.occurredAt >= start && evidence.occurredAt <= end {
            evidenceCount += 1
            switch evidence.kind {
            case .failedPlaylistRequest,
                 .failedSegmentRequest,
                 .failedContentKeyRequest,
                 .slowSegment:
                deliveryEvidence.append(evidence)
            case .variantSwitch,
                 .confirmedStall,
                 .terminalFailure,
                 .unexpectedMediaResponse:
                renditionEvidence.append(evidence)
            default:
                break
            }
        }

        let incidents = storyboard.incidents.filter {
            $0.startedAt <= end && ($0.endedAt ?? end) >= start
        }

        self.samples = samples
        self.waitingSamples = waitingSamples
        self.renditionSamples = renditionSamples
        self.deliveryEvidence = deliveryEvidence
        self.renditionEvidence = renditionEvidence
        self.evidenceCount = evidenceCount
        self.bookmarks = storyboard.bookmarks.filter {
            $0.capturedAt >= start && $0.capturedAt <= end
        }
        self.incidents = incidents
        self.recoveryBoundaries = incidents.compactMap { incident in
            incident.endedAt.map {
                RecoveryBoundary(id: incident.id, endedAt: $0)
            }
        }
        self.bufferScaleMaximum = max(maximumBuffer, 10)
        self.deliveryScaleMaximum = max(maximumDelivery, 1_000_000)
        self.renditionScaleMaximum = max(maximumRendition, 1080)
    }

    private static func renditionHeight(_ resolution: String?) -> Double? {
        guard let resolution,
              let last = resolution.split(separator: "×").last,
              let value = Double(last),
              value > 0 else {
            return nil
        }
        return value
    }
}

private struct RenditionSample: Identifiable {
    let id: UUID
    let capturedAt: Date
    let height: Double
    let resolution: String?
}

private struct RecoveryBoundary: Identifiable {
    let id: UUID
    let endedAt: Date
}
#endif
