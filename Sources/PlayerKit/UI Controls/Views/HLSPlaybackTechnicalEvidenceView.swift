#if os(macOS)
import SwiftUI

struct HLSPlaybackTechnicalEvidenceView: View {
    let snapshot: PlaybackDiagnosticsSnapshot

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                inspectorTitle
                section("Monitoring & Coverage", systemImage: "scope") {
                    row("Availability", snapshot.session.availability.title)
                    row(
                        "Backend",
                        snapshot.session.availability == .noPlayerItem
                            ? "Not measured"
                            : snapshot.session.backend
                    )
                    row(
                        "Monitor attached",
                        hasPlaybackItem
                            ? (snapshot.session.monitorAttached ? "Yes" : "No")
                            : "Not measured"
                    )
                    row(
                        "Session ID",
                        snapshot.session.sessionID?.uuidString ?? "Not measured",
                        monospaced: true
                    )
                    row(
                        "Asset ID",
                        snapshot.session.assetIdentifier ?? "Not measured",
                        monospaced: true
                    )
                    row(
                        "Captured",
                        PlaybackDiagnosticsFormat.fullTime(snapshot.session.capturedAt)
                    )
                    row(
                        "Session started",
                        PlaybackDiagnosticsFormat.fullTime(
                            snapshot.storyboard.sessionStartedAt
                                ?? snapshot.session.startedAt
                        )
                    )
                    row(
                        "Session ended",
                        PlaybackDiagnosticsFormat.fullTime(
                            snapshot.storyboard.endedAt
                        )
                    )
                    if let monitor = snapshot.monitor {
                        row("Observer state", monitor.streamState.rawValue)
                        row("Fallback reason", monitor.fallbackReason?.rawValue ?? "None")
                        row(
                            "Observer failure",
                            errorDescription(monitor.streamFailure)
                        )
                    }
                }

                section("Playback & Buffer", systemImage: "play.rectangle") {
                    row("Item status", snapshot.playback.itemStatus)
                    row("Time control", snapshot.playback.timeControlStatus)
                    row(
                        "Waiting reason",
                        hasPlaybackItem
                            ? (snapshot.playback.waitingReason ?? "None")
                            : "Not measured"
                    )
                    row("Rate", playbackRate)
                    row(
                        "Media time",
                        PlaybackDiagnosticsFormat.seconds(snapshot.playback.currentTime)
                    )
                    row(
                        "Duration",
                        PlaybackDiagnosticsFormat.seconds(snapshot.playback.duration)
                    )
                    row(
                        "Buffered until",
                        PlaybackDiagnosticsFormat.seconds(snapshot.playback.bufferedUntil)
                    )
                    row(
                        "Buffer headroom",
                        PlaybackDiagnosticsFormat.seconds(snapshot.playback.bufferHeadroom)
                    )
                    row(
                        "Likely to keep up",
                        hasPlaybackItem
                            ? (snapshot.playback.isPlaybackLikelyToKeepUp ? "Yes" : "No")
                            : "Not measured"
                    )
                    row(
                        "Buffer empty",
                        hasPlaybackItem
                            ? (snapshot.playback.isPlaybackBufferEmpty ? "Yes" : "No")
                            : "Not measured"
                    )
                    row(
                        "Buffer full",
                        hasPlaybackItem
                            ? (snapshot.playback.isPlaybackBufferFull ? "Yes" : "No")
                            : "Not measured"
                    )
                    row(
                        "Loaded ranges",
                        hasPlaybackItem
                            ? String(snapshot.playback.loadedRangeCount)
                            : "Not measured"
                    )
                    row(
                        "Seekable ranges",
                        hasPlaybackItem
                            ? String(snapshot.playback.seekableRangeCount)
                            : "Not measured"
                    )
                }

                section("Delivery", systemImage: "network") {
                    row(
                        "Observed bitrate",
                        PlaybackDiagnosticsFormat.bitRate(snapshot.network.observedBitRate)
                    )
                    row(
                        "Indicated bitrate",
                        PlaybackDiagnosticsFormat.bitRate(snapshot.network.indicatedBitRate)
                    )
                    row(
                        "Average video bitrate",
                        PlaybackDiagnosticsFormat.bitRate(snapshot.network.averageVideoBitRate)
                    )
                    row(
                        "Average audio bitrate",
                        PlaybackDiagnosticsFormat.bitRate(snapshot.network.averageAudioBitRate)
                    )
                    row("Bytes transferred", transferredBytes)
                    row(
                        "Transfer duration",
                        PlaybackDiagnosticsFormat.seconds(snapshot.network.transferDuration)
                    )
                    row(
                        "Segments downloaded",
                        PlaybackDiagnosticsFormat.seconds(
                            snapshot.network.segmentsDownloadedDuration
                        )
                    )
                    row(
                        "Media requests",
                        PlaybackDiagnosticsFormat.integer(snapshot.network.mediaRequestCount)
                    )
                    row(
                        "Access-log stalls",
                        PlaybackDiagnosticsFormat.integer(snapshot.network.numberOfStalls)
                    )
                    row(
                        "Overdue downloads",
                        PlaybackDiagnosticsFormat.integer(snapshot.network.overdueDownloadCount)
                    )
                    row(
                        "Dropped frames",
                        PlaybackDiagnosticsFormat.integer(
                            snapshot.network.droppedVideoFrameCount
                        )
                    )
                    row(
                        "Typed playlists",
                        monitorValue { String($0.playlistRequestCount) }
                    )
                    row(
                        "Typed segments",
                        monitorValue { String($0.segmentRequestCount) }
                    )
                    row(
                        "Failed playlists",
                        monitorValue { String($0.failedPlaylistRequestCount) }
                    )
                    row(
                        "Failed segments",
                        monitorValue { String($0.failedSegmentRequestCount) }
                    )
                    row(
                        "Slow segments",
                        monitorValue { String($0.slowDelivery.totalCount) }
                    )
                    row(
                        "Worst segment ratio",
                        monitorValue {
                            $0.slowDelivery.worstRatio.map {
                                String(format: "%.2f×", $0)
                            } ?? "Not measured"
                        }
                    )
                }

                section("Startup, Waits & Seeks", systemImage: "timer") {
                    row("Startup to playing", startupToPlaying)
                    row(
                        "Startup to likely-to-keep-up",
                        startupToLikelyToKeepUp
                    )
                    row("Confirmed rebuffers", confirmedRebufferCount)
                    row("Active rebuffer time", activeRebufferDuration)
                    row("Total rebuffer time", totalRebufferDuration)
                    row(
                        "Initial waits",
                        snapshot.monitor.map { String($0.waiting.initialWaitCount) }
                            ?? "Not measured"
                    )
                    row(
                        "Post-start waits",
                        snapshot.monitor.map { String($0.waiting.postStartWaitCount) }
                            ?? "Not measured"
                    )
                    row(
                        "Seek waits",
                        snapshot.monitor.map { String($0.waiting.seekWaitCount) }
                            ?? "Not measured"
                    )
                    row(
                        "Current wait",
                        monitorValue {
                            $0.waiting.currentKind?.rawValue ?? "None"
                        }
                    )
                    row(
                        "Current wait duration",
                        PlaybackDiagnosticsFormat.seconds(
                            snapshot.monitor?.waiting.currentWaitDuration
                        )
                    )
                    row(
                        "Total measured wait",
                        snapshot.monitor.map {
                            PlaybackDiagnosticsFormat.seconds(
                                $0.waiting.totalWaitDuration
                            )
                        } ?? "Not measured"
                    )
                    row(
                        "Seeks started",
                        snapshot.monitor.map { String($0.seeks.startedCount) }
                            ?? "Not measured"
                    )
                    row(
                        "Seeks completed",
                        snapshot.monitor.map { String($0.seeks.completedCount) }
                            ?? "Not measured"
                    )
                }

                section("Rendition & Tracks", systemImage: "film.stack") {
                    row("Resolution", snapshot.playback.resolution ?? "Not measured")
                    row(
                        "Frame rate",
                        snapshot.playback.frameRate.map {
                            String(format: "%.2f fps", $0)
                        } ?? "Not measured"
                    )
                    row(
                        "Variant switches",
                        snapshot.monitor.map {
                            String($0.variantSwitches.totalCount)
                        } ?? "Not measured"
                    )
                    row(
                        "Variant switch failures",
                        snapshot.monitor.map {
                            String($0.variantSwitches.failedCount)
                        } ?? "Not measured"
                    )
                    tracks(
                        "Audio tracks",
                        itemName: "Audio track",
                        tracks: snapshot.audioTracks
                    )
                    tracks(
                        "Subtitle tracks",
                        itemName: "Subtitle track",
                        tracks: snapshot.subtitleTracks
                    )
                }

                section(
                    "Recent Requests",
                    systemImage: "list.bullet.rectangle"
                ) {
                    if let trace = snapshot.monitor?.requestTrace {
                        row("Received", String(trace.receivedCount))
                        row("Retained", String(trace.entries.count))
                        row("Dropped", String(trace.droppedCount))
                        if trace.entries.isEmpty {
                            emptyRow("No typed request evidence retained.")
                        } else {
                            ForEach(
                                Array(trace.entries.reversed().enumerated()),
                                id: \.offset
                            ) { _, entry in
                                requestRow(entry)
                            }
                        }
                    } else {
                        emptyRow("Typed request trace is not available in this coverage mode.")
                    }
                }

                section("System & Error Logs", systemImage: "exclamationmark.bubble") {
                    row(
                        "Error-log entries",
                        hasPlaybackItem
                            ? String(snapshot.errorLogEventCount)
                            : "Not measured"
                    )
                    if !hasPlaybackItem {
                        emptyRow("Error logs are not measured without an active item.")
                    } else if snapshot.recentErrors.isEmpty {
                        emptyRow("No sanitized AVFoundation errors retained.")
                    } else {
                        ForEach(
                            Array(snapshot.recentErrors.enumerated()),
                            id: \.offset
                        ) { _, error in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(errorDescription(error))
                                    .font(.system(size: 10, design: .monospaced))
                                Text(PlaybackDiagnosticsFormat.fullTime(error.occurredAt))
                                    .font(.caption2)
                                    .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
                            }
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .bottom) {
                                divider
                            }
                        }
                    }

                    if snapshot.monitor == nil,
                       snapshot.recentHealthEvents.isEmpty {
                        emptyRow(
                            "Classifier signals are not measured without an active monitor."
                        )
                    } else if snapshot.recentHealthEvents.isEmpty {
                        emptyRow("No retained classifier signals.")
                    } else {
                        ForEach(
                            Array(snapshot.recentHealthEvents.reversed().enumerated()),
                            id: \.offset
                        ) { _, event in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.signalKind.rawValue)
                                    .font(.system(size: 10, weight: .semibold))
                                Text(
                                    "\(event.mediaType.rawValue) · \(event.confidence.rawValue) evidence · \(PlaybackDiagnosticsFormat.fullTime(event.occurredAt))"
                                )
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
                            }
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .bottom) {
                                divider
                            }
                        }
                    }
                }

                section("Collection & Calibration", systemImage: "tray.full") {
                    row(
                        "Storyboard samples",
                        "\(snapshot.storyboard.samples.count) / \(PlaybackDiagnosticsSessionReducer.sampleCapacity)"
                    )
                    row(
                        "High-signal evidence",
                        "\(snapshot.storyboard.evidence.count) / \(PlaybackDiagnosticsSessionReducer.evidenceCapacity)"
                    )
                    row(
                        "Automatic incidents",
                        "\(snapshot.storyboard.incidents.count) / \(PlaybackDiagnosticsSessionReducer.incidentCapacity)"
                    )
                    row(
                        "Bookmarks",
                        "\(snapshot.storyboard.bookmarks.count) / \(PlaybackDiagnosticsSessionReducer.bookmarkCapacity)"
                    )
                    row("Classifier candidates", classifierValue(\.candidateCount))
                    row("Classifier emitted", classifierValue(\.emittedCount))
                    row("Classifier suppressed", classifierValue(\.suppressedCount))
                    row("Classifier cap", classifierValue(\.sampleCap))
                    row("Health signals received", String(snapshot.history.receivedCount))
                    row("Health signals retained", String(snapshot.history.retainedCount))
                    row("Health signals dropped", String(snapshot.history.droppedCount))
                    row("Health signals cleared", String(snapshot.history.clearedCount))
                }
            }
        }
        .background(PlaybackDiagnosticsTheme.recessed)
        .foregroundStyle(PlaybackDiagnosticsTheme.primary)
        .accessibilityIdentifier("player.diagnostics.technical.evidence")
    }

    private var hasPlaybackItem: Bool {
        snapshot.playback.itemStatus != "unavailable"
    }

    private var playbackRate: String {
        guard hasPlaybackItem,
              let rate = snapshot.playback.rate,
              rate.isFinite else {
            return "Not measured"
        }
        return String(format: "%.2f×", rate)
    }

    private var transferredBytes: String {
        snapshot.network.bytesTransferred.map {
            "\($0) B"
        } ?? "Not measured"
    }

    private var startupToPlaying: String {
        PlaybackDiagnosticsFormat.seconds(
            interval(
                from: snapshot.storyboard.sessionStartedAt
                    ?? snapshot.session.startedAt,
                to: snapshot.storyboard.firstPlayingAt
            )
        )
    }

    private var startupToLikelyToKeepUp: String {
        PlaybackDiagnosticsFormat.seconds(
            snapshot.monitor?.likelyToKeepUp.initial?.timeTaken
                ?? interval(
                    from: snapshot.storyboard.sessionStartedAt
                        ?? snapshot.session.startedAt,
                    to: snapshot.storyboard.firstLikelyToKeepUpAt
                )
        )
    }

    private func interval(from start: Date?, to end: Date?) -> TimeInterval? {
        guard let start, let end else { return nil }
        let value = end.timeIntervalSince(start)
        return value.isFinite && value >= 0 ? value : nil
    }

    private var confirmedRebuffers: [PlaybackDiagnosticsAutomaticIncident] {
        snapshot.storyboard.incidents.filter {
            $0.kind == .confirmedRebuffer
        }
    }

    private var confirmedRebufferCount: String {
        guard snapshot.monitor != nil else { return "Not measured" }
        return String(confirmedRebuffers.count)
    }

    private var activeRebufferDuration: String {
        guard snapshot.monitor != nil else { return "Not measured" }
        let total = confirmedRebuffers
            .filter { $0.state == .active }
            .map { $0.duration(at: snapshot.session.capturedAt) }
            .reduce(0, +)
        return PlaybackDiagnosticsFormat.seconds(total)
    }

    private var totalRebufferDuration: String {
        guard snapshot.monitor != nil else { return "Not measured" }
        let total = confirmedRebuffers
            .map { $0.duration(at: snapshot.session.capturedAt) }
            .reduce(0, +)
        return PlaybackDiagnosticsFormat.seconds(total)
    }

    private func monitorValue(
        _ value: (PlaybackHealthMonitorTelemetry) -> String
    ) -> String {
        snapshot.monitor.map(value) ?? "Not measured"
    }

    private var inspectorTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Technical Evidence")
                .font(.system(size: 16, weight: .bold))
            Text(
                "Sanitized requests, tracks, logs, monitoring internals, and calibration."
            )
            .font(.system(size: 10))
            .foregroundStyle(PlaybackDiagnosticsTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PlaybackDiagnosticsTheme.elevated)
        .overlay(alignment: .bottom) {
            divider
        }
    }

    private func section<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PlaybackDiagnosticsTheme.primary)
        }
        .tint(PlaybackDiagnosticsTheme.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            divider
        }
    }

    private func row(
        _ label: String,
        _ value: String,
        monospaced: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
            Spacer(minLength: 8)
            Text(value)
                .font(
                    .system(
                        size: 9,
                        design: monospaced ? .monospaced : .default
                    )
                )
                .foregroundStyle(PlaybackDiagnosticsTheme.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            divider
        }
        .accessibilityElement(children: .combine)
    }

    private func tracks(
        _ title: String,
        itemName: String,
        tracks: [PlaybackDiagnosticsTrack]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.bold())
                .tracking(0.5)
                .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
                .padding(.top, 8)
            if tracks.isEmpty {
                emptyRow(
                    hasPlaybackItem
                        ? "No tracks reported."
                        : "Tracks are not measured without an active item."
                )
            } else {
                ForEach(Array(tracks.enumerated()), id: \.offset) { _, track in
                    HStack(spacing: 6) {
                        Image(
                            systemName: track.isSelected
                                ? "checkmark.circle.fill"
                                : "circle"
                        )
                        .foregroundStyle(
                            track.isSelected
                                ? PlaybackDiagnosticsTheme.green
                                : PlaybackDiagnosticsTheme.tertiary
                        )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(itemName)
                                .font(.caption2.weight(.medium))
                            Text(trackMetadata(track))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func trackMetadata(_ track: PlaybackDiagnosticsTrack) -> String {
        let language = safeTrackLanguage(track.languageCode)
            ?? "Language not measured"
        let identifier = safeTrackIdentifier(track.identifier)
            .map { "ID \($0)" }
            ?? "ID not measured"
        return "\(language) · \(identifier)"
    }

    private func safeTrackLanguage(_ language: String?) -> String? {
        guard let language,
              !language.isEmpty,
              language.utf8.count <= 35,
              language.utf8.allSatisfy({
                  (65...90).contains($0)
                      || (97...122).contains($0)
                      || (48...57).contains($0)
                      || $0 == 45
              }) else {
            return nil
        }
        return language
    }

    private func safeTrackIdentifier(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let normalized = identifier.lowercased()
        guard normalized.utf8.count == 71,
              normalized.hasPrefix("sha256:"),
              normalized.dropFirst(7).utf8.allSatisfy({
                  (48...57).contains($0) || (97...102).contains($0)
              }) else {
            return nil
        }
        return String(normalized.prefix(19)) + "…"
    }

    private func requestRow(_ entry: PlaybackHealthRequestTraceEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Label(
                    entry.kind.rawValue,
                    systemImage: entry.didFail
                        ? "xmark.octagon"
                        : "arrow.down.circle"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(
                    entry.didFail
                        ? PlaybackDiagnosticsTheme.danger
                        : PlaybackDiagnosticsTheme.secondary
                )
                Spacer()
                Text(PlaybackDiagnosticsFormat.fullTime(entry.occurredAt))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
            }

            Text(requestSummary(entry))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            divider
        }
        .accessibilityElement(children: .combine)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(PlaybackDiagnosticsTheme.tertiary)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle()
            .fill(PlaybackDiagnosticsTheme.divider)
            .frame(height: 1)
    }

    private func classifierValue(
        _ keyPath: KeyPath<PlaybackHealthClassifierTelemetry, Int>
    ) -> String {
        snapshot.monitor.map {
            String($0.classifier[keyPath: keyPath])
        } ?? "Not measured"
    }

    private func requestSummary(_ entry: PlaybackHealthRequestTraceEntry) -> String {
        var parts = [
            entry.mediaType.rawValue,
            entry.mimeCategory?.rawValue ?? "MIME not measured",
            PlaybackDiagnosticsFormat.seconds(entry.requestDuration)
        ]
        if let status = entry.httpStatusCode {
            parts.append("HTTP \(status)")
        }
        if let ratio = entry.segmentDeliveryRatio {
            parts.append(String(format: "%.2f× media duration", ratio))
        }
        return parts.joined(separator: " · ")
    }

    private func errorDescription(_ error: PlaybackDiagnosticsError?) -> String {
        guard let error else { return "None" }
        return "\(error.domain ?? "Unlisted domain") / \(error.code)"
    }
}
#endif
