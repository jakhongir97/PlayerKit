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
        VStack(spacing: 0) {
            timelineHeader

            VStack(spacing: 0) {
                lane(title: "Playback", subtitle: "State · buffer") {
                    playbackChart
                }

                lane(title: "Delivery", subtitle: "Observed · indicated") {
                    deliveryChart
                }

                lane(title: "Rendition", subtitle: "Quality · events") {
                    renditionChart
                }
            }
            .background(PlaybackDiagnosticsTheme.recessed)

            timeFooter
        }
        .onChange(of: selectedDate) { _, date in
            guard let date else { return }
            if let selectedIncidentID,
               storyboard.incidents.first(where: {
                   $0.id == selectedIncidentID
               })?.startedAt == date {
                return
            }
            selectIncident(at: date)
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
            .font(.system(size: 9, weight: .medium))
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
                .font(.system(size: 8))
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
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(PlaybackDiagnosticsTheme.secondary)
                Text(subtitle)
                    .font(.system(size: 8))
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

    private var playbackChart: some View {
        Chart {
            incidentBands(maxY: bufferScaleMaximum)

            ForEach(visibleSamples) { sample in
                RectangleMark(
                    xStart: .value("State start", sample.capturedAt.addingTimeInterval(-0.5)),
                    xEnd: .value("State end", sample.capturedAt.addingTimeInterval(0.5)),
                    yStart: .value("State minimum", 0),
                    yEnd: .value("State maximum", bufferScaleMaximum)
                )
                .foregroundStyle(stateColor(sample.state).opacity(0.10))
            }

            ForEach(visibleSamples) { sample in
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

            ForEach(visibleSamples.filter { $0.state == .waiting }) { sample in
                PointMark(
                    x: .value("Wait time", sample.capturedAt),
                    y: .value("Wait buffer", sample.bufferHeadroom ?? 0)
                )
                .foregroundStyle(PlaybackDiagnosticsTheme.warning)
                .symbolSize(20)
            }

            recoveryBoundaries(maxY: bufferScaleMaximum)
            nowCursor(maxY: bufferScaleMaximum)
        }
        .chartXScale(domain: visibleStart ... visibleEnd)
        .chartYScale(domain: 0 ... bufferScaleMaximum)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                AxisGridLine()
                    .foregroundStyle(PlaybackDiagnosticsTheme.divider)
                AxisValueLabel()
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
            }
        }
        .chartXSelection(value: $selectedDate)
        .accessibilityLabel("Playback state and buffer lane")
        .accessibilityValue(playbackAccessibilityValue)
    }

    private var deliveryChart: some View {
        Chart {
            incidentBands(maxY: deliveryScaleMaximum)
            deliveryLines()
            deliveryEvidenceMarks()
            recoveryBoundaries(maxY: deliveryScaleMaximum)
            nowCursor(maxY: deliveryScaleMaximum)
        }
        .chartXScale(domain: visibleStart ... visibleEnd)
        .chartYScale(domain: 0 ... deliveryScaleMaximum)
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
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
            }
        }
        .chartXSelection(value: $selectedDate)
        .accessibilityLabel("Observed versus indicated delivery lane")
        .accessibilityValue(deliveryAccessibilityValue)
    }

    private var renditionChart: some View {
        Chart {
            incidentBands(maxY: renditionScaleMaximum)
            renditionLines()
            renditionEvidenceMarks()
            bookmarkMarks()
            recoveryBoundaries(maxY: renditionScaleMaximum)
            nowCursor(maxY: renditionScaleMaximum)
        }
        .chartXScale(domain: visibleStart ... visibleEnd)
        .chartYScale(domain: 0 ... renditionScaleMaximum)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) {
                AxisGridLine()
                    .foregroundStyle(PlaybackDiagnosticsTheme.divider)
                AxisTick()
                    .foregroundStyle(PlaybackDiagnosticsTheme.divider)
                AxisValueLabel(format: .dateTime.minute().second())
                    .font(.system(size: 8, design: .monospaced))
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
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
            }
        }
        .chartXSelection(value: $selectedDate)
        .accessibilityLabel("Rendition and high-signal event lane")
        .accessibilityValue(renditionAccessibilityValue)
    }

    @ChartContentBuilder
    private func deliveryLines() -> some ChartContent {
        ForEach(visibleSamples) { sample in
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
    private func deliveryEvidenceMarks() -> some ChartContent {
        ForEach(deliveryEvidence) { evidence in
            PointMark(
                x: .value("Evidence time", evidence.occurredAt),
                y: .value("Evidence", deliveryScaleMaximum * 0.08)
            )
            .foregroundStyle(
                PlaybackDiagnosticsTheme.color(for: evidence.level)
            )
            .symbolSize(evidence.level >= .warning ? 32 : 18)
        }
    }

    @ChartContentBuilder
    private func renditionLines() -> some ChartContent {
        ForEach(visibleRenditionSamples) { sample in
            if let height = renditionHeight(sample.resolution) {
                LineMark(
                    x: .value("Time", sample.capturedAt),
                    y: .value("Rendition height", height)
                )
                .foregroundStyle(Color.blue)
                .lineStyle(StrokeStyle(lineWidth: 2.2))
                .interpolationMethod(.stepEnd)
            }
        }
    }

    @ChartContentBuilder
    private func renditionEvidenceMarks() -> some ChartContent {
        ForEach(renditionEvidence) { evidence in
            RuleMark(x: .value("Event time", evidence.occurredAt))
                .foregroundStyle(
                    PlaybackDiagnosticsTheme.color(for: evidence.level).opacity(0.7)
                )
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))

            PointMark(
                x: .value("Event time", evidence.occurredAt),
                y: .value("Event", renditionScaleMaximum * 0.12)
            )
            .foregroundStyle(
                PlaybackDiagnosticsTheme.color(for: evidence.level)
            )
            .symbolSize(evidence.level >= .warning ? 36 : 20)
        }
    }

    @ChartContentBuilder
    private func bookmarkMarks() -> some ChartContent {
        ForEach(visibleBookmarks) { bookmark in
            RuleMark(x: .value("Bookmark", bookmark.capturedAt))
                .foregroundStyle(PlaybackDiagnosticsTheme.primary.opacity(0.65))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: .center) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(PlaybackDiagnosticsTheme.primary)
                        .accessibilityLabel("Saved moment")
                }
        }
    }

    @ChartContentBuilder
    private func incidentBands(maxY: Double) -> some ChartContent {
        ForEach(visibleIncidents) { incident in
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
    private func recoveryBoundaries(maxY: Double) -> some ChartContent {
        ForEach(visibleIncidents.compactMap { incident -> RecoveryBoundary? in
            guard let endedAt = incident.endedAt else { return nil }
            return RecoveryBoundary(id: incident.id, endedAt: endedAt)
        }) { boundary in
            RuleMark(x: .value("Recovery", boundary.endedAt))
                .foregroundStyle(PlaybackDiagnosticsTheme.green.opacity(0.65))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
        }
    }

    @ChartContentBuilder
    private func nowCursor(maxY: Double) -> some ChartContent {
        RuleMark(x: .value("Now", nowDate))
            .foregroundStyle(PlaybackDiagnosticsTheme.green.opacity(0.85))
            .lineStyle(StrokeStyle(lineWidth: 1))
            .annotation(position: .top, alignment: .trailing) {
                Text("NOW")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(PlaybackDiagnosticsTheme.green)
            }
    }

    private var timeFooter: some View {
        HStack {
            Text(PlaybackDiagnosticsFormat.shortTime(visibleStart))
            Spacer()
            Text("\(Int(zoomSeconds)) s window")
            Spacer()
            Text(PlaybackDiagnosticsFormat.shortTime(visibleEnd))
        }
        .font(.system(size: 8, design: .monospaced))
        .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
        .padding(.horizontal, 92)
        .frame(height: 20)
        .background(PlaybackDiagnosticsTheme.elevated)
        .accessibilityElement(children: .combine)
    }

    private var nowDate: Date {
        min(storyboard.samples.last?.capturedAt ?? displayTime, visibleEnd)
    }

    private var visibleEnd: Date {
        storyboard.samples.last?.capturedAt ?? displayTime
    }

    private var visibleStart: Date {
        visibleEnd.addingTimeInterval(-zoomSeconds)
    }

    private var visibleSamples: [PlaybackDiagnosticsSample] {
        storyboard.samples.filter {
            $0.capturedAt >= visibleStart && $0.capturedAt <= visibleEnd
        }
    }

    private var visibleRenditionSamples: [PlaybackDiagnosticsSample] {
        visibleSamples.filter { renditionHeight($0.resolution) != nil }
    }

    private var visibleEvidence: [PlaybackDiagnosticsEvidence] {
        storyboard.evidence.filter {
            $0.occurredAt >= visibleStart && $0.occurredAt <= visibleEnd
        }
    }

    private var deliveryEvidence: [PlaybackDiagnosticsEvidence] {
        visibleEvidence.filter {
            switch $0.kind {
            case .failedPlaylistRequest,
                 .failedSegmentRequest,
                 .failedContentKeyRequest,
                 .slowSegment:
                return true
            default:
                return false
            }
        }
    }

    private var renditionEvidence: [PlaybackDiagnosticsEvidence] {
        visibleEvidence.filter {
            switch $0.kind {
            case .variantSwitch,
                 .confirmedStall,
                 .terminalFailure,
                 .unexpectedMediaResponse:
                return true
            default:
                return false
            }
        }
    }

    private var visibleBookmarks: [PlaybackDiagnosticsBookmark] {
        storyboard.bookmarks.filter {
            $0.capturedAt >= visibleStart && $0.capturedAt <= visibleEnd
        }
    }

    private var visibleIncidents: [PlaybackDiagnosticsAutomaticIncident] {
        storyboard.incidents.filter {
            $0.startedAt <= visibleEnd && ($0.endedAt ?? visibleEnd) >= visibleStart
        }
    }

    private var bufferScaleMaximum: Double {
        max(visibleSamples.compactMap(\.bufferHeadroom).max() ?? 0, 10)
    }

    private var deliveryScaleMaximum: Double {
        max(
            visibleSamples.flatMap {
                [$0.observedBitRate, $0.indicatedBitRate].compactMap { $0 }
            }.max() ?? 0,
            1_000_000
        )
    }

    private var renditionScaleMaximum: Double {
        max(visibleRenditionSamples.compactMap {
            renditionHeight($0.resolution)
        }.max() ?? 0, 1080)
    }

    private var playbackAccessibilityValue: String {
        guard let latest = visibleSamples.last else { return "No measured samples" }
        return "\(latest.state.rawValue), buffer \(PlaybackDiagnosticsFormat.seconds(latest.bufferHeadroom))"
    }

    private var deliveryAccessibilityValue: String {
        guard let latest = visibleSamples.last else { return "No measured samples" }
        return "Observed \(PlaybackDiagnosticsFormat.bitRate(latest.observedBitRate)), indicated \(PlaybackDiagnosticsFormat.bitRate(latest.indicatedBitRate))"
    }

    private var renditionAccessibilityValue: String {
        let latest = visibleRenditionSamples.last?.resolution ?? "Not measured"
        return "\(latest), \(visibleEvidence.count) retained events"
    }

    private func selectIncident(at date: Date) {
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

    private func renditionHeight(_ resolution: String?) -> Double? {
        guard let resolution else { return nil }
        let components = resolution.split(separator: "×")
        guard let last = components.last,
              let value = Double(last),
              value > 0 else {
            return nil
        }
        return value
    }

    private func axisBitRate(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        return String(format: "%.0fK", value / 1_000)
    }
}

private struct RecoveryBoundary: Identifiable {
    let id: UUID
    let endedAt: Date
}
#endif
