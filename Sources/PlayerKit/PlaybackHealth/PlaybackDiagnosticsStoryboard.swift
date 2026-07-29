#if os(macOS)
import Foundation

enum PlaybackDiagnosticsSampleState: String, Equatable, Sendable {
    case playing
    case waiting
    case paused
    case unavailable
}

struct PlaybackDiagnosticsSample: Identifiable, Equatable, Sendable {
    let id: UUID
    let capturedAt: Date
    let sessionElapsed: TimeInterval?
    let mediaTime: Double?
    let state: PlaybackDiagnosticsSampleState
    let waitingReason: String?
    let playbackRate: Double?
    let isPlaybackLikelyToKeepUp: Bool?
    let isPlaybackBufferEmpty: Bool?
    let isPlaybackBufferFull: Bool?
    let bufferHeadroom: Double?
    let observedBitRate: Double?
    let indicatedBitRate: Double?
    let resolution: String?
    let frameRate: Double?
    let droppedVideoFrameCount: Int?
    let droppedVideoFrameDelta: Int?
    let renditionPeakBitRate: Double?
    let renditionAverageBitRate: Double?
    let renditionResolution: String?
    let renditionFrameRate: Double?
    let sessionID: UUID?
    let assetIdentifier: String?
    let availability: PlaybackDiagnosticsAvailability
}

enum PlaybackDiagnosticsEvidenceKind: String, Equatable, Hashable, Sendable {
    case playbackReady
    case playbackBegan
    case waitBegan
    case waitEnded
    case confirmedStall
    case recovery
    case failedPlaylistRequest
    case failedSegmentRequest
    case failedContentKeyRequest
    case errorLogEntry
    case slowSegment
    case deliveryPressure
    case unexpectedMediaResponse
    case variantSwitch
    case droppedFrames
    case terminalFailure
    case naturalEnd
    case bookmark
}

struct PlaybackDiagnosticsEvidence: Identifiable, Equatable, Sendable {
    let id: UUID
    let occurredAt: Date
    let mediaTime: Double?
    let kind: PlaybackDiagnosticsEvidenceKind
    let level: PlaybackDiagnosticsLevel
    let title: String
    let measurement: String?
}

enum PlaybackDiagnosticsIncidentKind: String, Equatable, Sendable {
    case slowStartup
    case confirmedRebuffer
    case deliveryStarvation
    case repeatedRequestFailures
    case unexpectedMediaResponse
    case contentKeyFailure
    case renditionDowngrade
    case abrThrashing
    case renderPressure
    case terminalFailure

    var title: String {
        switch self {
        case .slowStartup:
            return "Slow startup"
        case .confirmedRebuffer:
            return "Confirmed rebuffer"
        case .deliveryStarvation:
            return "Sustained delivery starvation"
        case .repeatedRequestFailures:
            return "Repeated request failures"
        case .unexpectedMediaResponse:
            return "Unexpected media response"
        case .contentKeyFailure:
            return "Content-key delivery failure"
        case .renditionDowngrade:
            return "Rendition downgrade"
        case .abrThrashing:
            return "Frequent rendition switching"
        case .renderPressure:
            return "Dropped-frame pressure"
        case .terminalFailure:
            return "Terminal playback failure"
        }
    }
}

enum PlaybackDiagnosticsIncidentState: String, Equatable, Sendable {
    case active
    case recovered
}

enum PlaybackDiagnosticsEvidenceStrength: String, Equatable, Sendable {
    case direct = "Direct measured evidence"
    case correlated = "Correlated measured evidence"
    case limited = "Limited measured evidence"
}

struct PlaybackDiagnosticsAutomaticIncident: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: PlaybackDiagnosticsIncidentKind
    let severity: PlaybackDiagnosticsLevel
    let startedAt: Date
    var lastObservedAt: Date
    var endedAt: Date?
    let impact: String
    let likelyCause: String
    var evidenceIDs: [UUID]
    var measuredValues: [String]
    let nextAction: String
    let evidenceStrength: PlaybackDiagnosticsEvidenceStrength

    var state: PlaybackDiagnosticsIncidentState {
        endedAt == nil ? .active : .recovered
    }

    func duration(at now: Date) -> TimeInterval {
        max((endedAt ?? now).timeIntervalSince(startedAt), 0)
    }
}

struct PlaybackDiagnosticsBookmark: Identifiable, Equatable, Sendable {
    let id: UUID
    let capturedAt: Date
    let sessionElapsed: TimeInterval?
    let mediaTime: Double?
    var nearbySampleIDs: [UUID]
    var nearbyEvidenceIDs: [UUID]
    let selectedAudioTrack: PlaybackDiagnosticsTrack?
    let itemStatus: String
    let timeControlStatus: String
    let waitingReason: String?
    let bufferHeadroom: Double?
    let resolution: String?
    let frameRate: Double?
    let observedBitRate: Double?
    let indicatedBitRate: Double?
    let accessLogStallCount: Int?
    let metricStallCount: Int?
    let observedHLSRequestCount: Int?
    let failedHLSRequestCount: Int?
    let postStartWaitCount: Int?
    let seekWaitCount: Int?
    let errorLogEventCount: Int

    init(
        id: UUID,
        capturedAt: Date,
        sessionElapsed: TimeInterval? = nil,
        mediaTime: Double?,
        nearbySampleIDs: [UUID] = [],
        nearbyEvidenceIDs: [UUID] = [],
        selectedAudioTrack: PlaybackDiagnosticsTrack?,
        itemStatus: String,
        timeControlStatus: String,
        waitingReason: String?,
        bufferHeadroom: Double?,
        resolution: String?,
        frameRate: Double?,
        observedBitRate: Double?,
        indicatedBitRate: Double?,
        accessLogStallCount: Int?,
        metricStallCount: Int?,
        observedHLSRequestCount: Int? = nil,
        failedHLSRequestCount: Int? = nil,
        postStartWaitCount: Int? = nil,
        seekWaitCount: Int? = nil,
        errorLogEventCount: Int
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.sessionElapsed = sessionElapsed
        self.mediaTime = mediaTime
        self.nearbySampleIDs = nearbySampleIDs
        self.nearbyEvidenceIDs = nearbyEvidenceIDs
        self.selectedAudioTrack = selectedAudioTrack
        self.itemStatus = itemStatus
        self.timeControlStatus = timeControlStatus
        self.waitingReason = waitingReason
        self.bufferHeadroom = bufferHeadroom
        self.resolution = resolution
        self.frameRate = frameRate
        self.observedBitRate = observedBitRate
        self.indicatedBitRate = indicatedBitRate
        self.accessLogStallCount = accessLogStallCount
        self.metricStallCount = metricStallCount
        self.observedHLSRequestCount = observedHLSRequestCount
        self.failedHLSRequestCount = failedHLSRequestCount
        self.postStartWaitCount = postStartWaitCount
        self.seekWaitCount = seekWaitCount
        self.errorLogEventCount = errorLogEventCount
    }
}

struct PlaybackDiagnosticsStoryboard: Equatable, Sendable {
    var sessionStartedAt: Date?
    var firstPlayingAt: Date?
    var firstLikelyToKeepUpAt: Date?
    var endedAt: Date?
    var samples: [PlaybackDiagnosticsSample]
    var evidence: [PlaybackDiagnosticsEvidence]
    var incidents: [PlaybackDiagnosticsAutomaticIncident]
    var bookmarks: [PlaybackDiagnosticsBookmark]

    init(
        sessionStartedAt: Date? = nil,
        firstPlayingAt: Date? = nil,
        firstLikelyToKeepUpAt: Date? = nil,
        endedAt: Date? = nil,
        samples: [PlaybackDiagnosticsSample],
        evidence: [PlaybackDiagnosticsEvidence],
        incidents: [PlaybackDiagnosticsAutomaticIncident],
        bookmarks: [PlaybackDiagnosticsBookmark]
    ) {
        self.sessionStartedAt = sessionStartedAt
        self.firstPlayingAt = firstPlayingAt
        self.firstLikelyToKeepUpAt = firstLikelyToKeepUpAt
        self.endedAt = endedAt
        self.samples = samples
        self.evidence = evidence
        self.incidents = incidents
        self.bookmarks = bookmarks
    }

    static let empty = Self(
        samples: [],
        evidence: [],
        incidents: [],
        bookmarks: []
    )
}

struct PlaybackDiagnosticsSessionReducer {
    static let sampleCapacity = 300
    static let evidenceCapacity = 120
    static let incidentCapacity = 50
    static let bookmarkCapacity = 20
    static let incidentEvidenceCapacity = 24
    static let incidentMeasurementCapacity = 12
    static let bookmarkReferenceCapacity = 6

    private static let candidateSampleCount = 3
    private static let candidateDuration: TimeInterval = 2
    private static let correlationWindow: TimeInterval = 30
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    private struct Identity: Equatable {
        let sessionID: UUID?
        let assetIdentifier: String?
        let backend: String
        let startedAt: Date?
    }

    private struct Cursor {
        let itemStatus: String
        let timeControlStatus: String
        let waitKind: PlaybackHealthWaitKind?
        let stallCount: Int
        let requestTraceReceivedCount: Int
        let failedContentKeyCount: Int
        let variantSwitchCount: Int
        let droppedFrameCount: Int?
        let likelyToKeepUpInitialAt: Date?
        let terminalFailureAt: Date?
        let naturalEndAt: Date?

        init(_ snapshot: PlaybackDiagnosticsSnapshot) {
            itemStatus = snapshot.playback.itemStatus
            timeControlStatus = snapshot.playback.timeControlStatus
            waitKind = snapshot.monitor?.waiting.currentKind
            stallCount = snapshot.monitor?.stallCount ?? 0
            requestTraceReceivedCount = snapshot.monitor?.requestTrace.receivedCount ?? 0
            failedContentKeyCount = snapshot.monitor?.contentKeys.failedCount ?? 0
            variantSwitchCount = snapshot.monitor?.variantSwitches.totalCount ?? 0
            droppedFrameCount = snapshot.network.droppedVideoFrameCount
            likelyToKeepUpInitialAt = snapshot.monitor?.likelyToKeepUp.initial?.occurredAt
            terminalFailureAt = snapshot.monitor?.terminalFailure?.occurredAt
            naturalEndAt = snapshot.monitor?.naturalEnd?.occurredAt
        }
    }

    private enum VariantDirection: Equatable {
        case up
        case down
        case lateral
        case unknown
    }

    private(set) var storyboard = PlaybackDiagnosticsStoryboard.empty
    private var identity: Identity?
    private var cursor: Cursor?
    private var lastIngestedAt: Date?
    private var lowBufferStartedAt: Date?
    private var lowBufferSampleCount = 0
    private var healthyRecoveryStartedAt: Date?
    private var healthyRecoverySampleCount = 0
    private var droppedFrameBurst = 0
    private var bookmarkSequence = 0
    private var seenEvidenceKeys = Set<String>()
    private var seenEvidenceKeyOrder: [String] = []

    mutating func reset() {
        storyboard = .empty
        identity = nil
        cursor = nil
        lastIngestedAt = nil
        resetLowBufferCandidate()
        resetHealthyRecoveryCandidate()
        droppedFrameBurst = 0
        bookmarkSequence = 0
        seenEvidenceKeys.removeAll(keepingCapacity: true)
        seenEvidenceKeyOrder.removeAll(keepingCapacity: true)
    }

    mutating func clearEvidence() {
        storyboard.evidence.removeAll(keepingCapacity: true)
        storyboard.incidents.removeAll(keepingCapacity: true)
        storyboard.bookmarks.removeAll(keepingCapacity: true)
        resetLowBufferCandidate()
        resetHealthyRecoveryCandidate()
        droppedFrameBurst = 0
        seenEvidenceKeys.removeAll(keepingCapacity: true)
        seenEvidenceKeyOrder.removeAll(keepingCapacity: true)
    }

    mutating func end(at endedAt: Date) {
        guard let startedAt = storyboard.sessionStartedAt,
              Self.isFinite(endedAt) else {
            return
        }
        let normalized = max(endedAt, startedAt)
        if let existing = storyboard.endedAt {
            storyboard.endedAt = min(existing, normalized)
        } else {
            storyboard.endedAt = normalized
        }
    }

    mutating func ingest(_ snapshot: PlaybackDiagnosticsSnapshot) {
        guard snapshot.playback.itemStatus != "unavailable" else { return }

        let nextIdentity = Identity(
            sessionID: snapshot.session.sessionID,
            assetIdentifier: snapshot.session.assetIdentifier,
            backend: snapshot.session.backend,
            startedAt: Self.finiteDate(snapshot.session.startedAt)
        )
        if let identity, identity != nextIdentity {
            reset()
        }
        identity = nextIdentity
        guard storyboard.endedAt == nil else { return }

        let now = snapshot.session.capturedAt
        guard Self.isFinite(now) else { return }
        if let lastIngestedAt, now <= lastIngestedAt {
            return
        }
        self.lastIngestedAt = now
        if storyboard.sessionStartedAt == nil {
            let suppliedStart = Self.finiteDate(snapshot.session.startedAt)
                .flatMap { $0 <= now ? $0 : nil }
            storyboard.sessionStartedAt = suppliedStart ?? now
        }

        updateSessionMilestones(snapshot, at: now)
        appendSample(from: snapshot)
        recordStateTransitions(snapshot, at: now)
        recordRequestEvidence(snapshot)
        recordHealthEvents(
            snapshot.recentHealthEvents,
            requestEntries: snapshot.monitor?.requestTrace.entries ?? [],
            latestStallAt: snapshot.monitor?.latestStallAt
        )
        recordFallbackTerminalFailure(snapshot, at: now)
        recordMonitorEvidence(snapshot)
        reduceIncidents(snapshot, at: now)
        cursor = Cursor(snapshot)
    }

    @discardableResult
    mutating func captureBookmark(
        from snapshot: PlaybackDiagnosticsSnapshot,
        at capturedAt: Date = Date()
    ) -> PlaybackDiagnosticsBookmark? {
        guard snapshot.playback.itemStatus != "unavailable" else { return nil }

        let nextIdentity = Identity(
            sessionID: snapshot.session.sessionID,
            assetIdentifier: snapshot.session.assetIdentifier,
            backend: snapshot.session.backend,
            startedAt: Self.finiteDate(snapshot.session.startedAt)
        )
        if let identity, identity != nextIdentity {
            reset()
        }
        identity = nextIdentity
        guard storyboard.endedAt == nil else { return nil }
        if storyboard.sessionStartedAt == nil {
            storyboard.sessionStartedAt = Self.finiteDate(snapshot.session.startedAt)
                ?? Self.finiteDate(snapshot.session.capturedAt)
                ?? Self.finiteDate(capturedAt)
        }

        bookmarkSequence += 1
        let nearbySamples = Self.nearbyIDs(
            storyboard.samples.map { ($0.id, $0.capturedAt) },
            to: capturedAt
        )
        let nearbyEvidence = Self.nearbyIDs(
            storyboard.evidence.map { ($0.id, $0.occurredAt) },
            to: capturedAt
        )
        let monitor = snapshot.monitor
        let bookmark = PlaybackDiagnosticsBookmark(
            id: stableID(
                "bookmark|\(Self.timestampKey(capturedAt))|\(bookmarkSequence)"
            ),
            capturedAt: capturedAt,
            sessionElapsed: sessionElapsed(at: capturedAt),
            mediaTime: Self.nonnegative(snapshot.playback.currentTime),
            nearbySampleIDs: nearbySamples,
            nearbyEvidenceIDs: nearbyEvidence,
            selectedAudioTrack: retainedPlaybackDiagnosticsAudioTrack(
                snapshot.audioTracks.first(where: \.isSelected)
            ),
            itemStatus: snapshot.playback.itemStatus,
            timeControlStatus: snapshot.playback.timeControlStatus,
            waitingReason: snapshot.playback.waitingReason,
            bufferHeadroom: snapshot.playback.bufferHeadroom,
            resolution: snapshot.playback.resolution,
            frameRate: snapshot.playback.frameRate,
            observedBitRate: snapshot.network.observedBitRate,
            indicatedBitRate: snapshot.network.indicatedBitRate,
            accessLogStallCount: snapshot.network.numberOfStalls,
            metricStallCount: monitor?.stallCount,
            observedHLSRequestCount: monitor?.observedHLSRequestCount,
            failedHLSRequestCount: monitor.map {
                $0.failedPlaylistRequestCount + $0.failedSegmentRequestCount
            },
            postStartWaitCount: monitor?.waiting.postStartWaitCount,
            seekWaitCount: monitor?.waiting.seekWaitCount,
            errorLogEventCount: snapshot.errorLogEventCount
        )
        storyboard.bookmarks.append(bookmark)
        if storyboard.bookmarks.count > Self.bookmarkCapacity {
            storyboard.bookmarks.removeFirst(
                storyboard.bookmarks.count - Self.bookmarkCapacity
            )
        }
        _ = appendEvidence(
            key: "bookmark|\(bookmark.id.uuidString)",
            occurredAt: capturedAt,
            mediaTime: bookmark.mediaTime,
            kind: .bookmark,
            level: .observation,
            title: "Saved moment",
            measurement: bookmark.bufferHeadroom.map {
                "Buffer headroom \(Self.seconds($0))"
            }
        )
        return bookmark
    }

    private mutating func appendSample(from snapshot: PlaybackDiagnosticsSnapshot) {
        let state: PlaybackDiagnosticsSampleState
        switch snapshot.playback.timeControlStatus {
        case "playing":
            state = .playing
        case "waiting":
            state = .waiting
        case "paused":
            state = .paused
        default:
            state = .unavailable
        }

        let rendition = snapshot.monitor?.variantSwitches.recentTransitions
            .last(where: \.succeeded)?
            .to
        let droppedFrames = Self.nonnegative(snapshot.network.droppedVideoFrameCount)
        let droppedDelta: Int?
        if let droppedFrames,
           let previous = cursor?.droppedFrameCount,
           previous >= 0,
           droppedFrames >= previous {
            droppedDelta = droppedFrames - previous
        } else {
            droppedDelta = nil
        }
        storyboard.samples.append(
            PlaybackDiagnosticsSample(
                id: stableID(
                    "sample|\(Self.timestampKey(snapshot.session.capturedAt))"
                ),
                capturedAt: snapshot.session.capturedAt,
                sessionElapsed: sessionElapsed(at: snapshot.session.capturedAt),
                mediaTime: Self.nonnegative(snapshot.playback.currentTime),
                state: state,
                waitingReason: snapshot.playback.waitingReason,
                playbackRate: Self.finite(snapshot.playback.rate),
                isPlaybackLikelyToKeepUp: snapshot.playback.isPlaybackLikelyToKeepUp,
                isPlaybackBufferEmpty: snapshot.playback.isPlaybackBufferEmpty,
                isPlaybackBufferFull: snapshot.playback.isPlaybackBufferFull,
                bufferHeadroom: Self.nonnegative(snapshot.playback.bufferHeadroom),
                observedBitRate: Self.nonnegative(snapshot.network.observedBitRate),
                indicatedBitRate: Self.nonnegative(snapshot.network.indicatedBitRate),
                resolution: snapshot.playback.resolution,
                frameRate: Self.positive(snapshot.playback.frameRate),
                droppedVideoFrameCount: droppedFrames,
                droppedVideoFrameDelta: droppedDelta,
                renditionPeakBitRate: Self.positive(rendition?.peakBitRate),
                renditionAverageBitRate: Self.positive(rendition?.averageBitRate),
                renditionResolution: rendition?.resolution,
                renditionFrameRate: Self.positive(rendition?.frameRate),
                sessionID: snapshot.session.sessionID,
                assetIdentifier: snapshot.session.assetIdentifier,
                availability: snapshot.session.availability
            )
        )
        if storyboard.samples.count > Self.sampleCapacity {
            storyboard.samples.removeFirst(
                storyboard.samples.count - Self.sampleCapacity
            )
        }
        pruneBookmarkSampleReferences()
    }

    private mutating func recordStateTransitions(
        _ snapshot: PlaybackDiagnosticsSnapshot,
        at now: Date
    ) {
        guard let cursor else { return }

        if cursor.itemStatus != "ready", snapshot.playback.itemStatus == "ready" {
            _ = appendEvidence(
                key: "ready|\(Self.timestampKey(now))",
                occurredAt: now,
                mediaTime: snapshot.playback.currentTime,
                kind: .playbackReady,
                level: .observation,
                title: "Playback became ready",
                measurement: nil
            )
        }
        if cursor.timeControlStatus != "playing",
           snapshot.playback.timeControlStatus == "playing" {
            _ = appendEvidence(
                key: "playing|\(Self.timestampKey(now))",
                occurredAt: now,
                mediaTime: snapshot.playback.currentTime,
                kind: .playbackBegan,
                level: .observation,
                title: "Playback began",
                measurement: nil
            )
        }

        let currentWait = snapshot.monitor?.waiting.currentKind
        if cursor.waitKind != currentWait {
            if let currentWait {
                _ = appendEvidence(
                    key: "wait-began|\(currentWait.rawValue)|\(Self.timestampKey(now))",
                    occurredAt: now,
                    mediaTime: snapshot.playback.currentTime,
                    kind: .waitBegan,
                    level: currentWait == .postStart ? .notice : .observation,
                    title: "\(Self.waitTitle(currentWait)) began",
                    measurement: snapshot.monitor?.waiting.currentWaitDuration.map(Self.seconds)
                )
            } else if let previousWait = cursor.waitKind {
                _ = appendEvidence(
                    key: "wait-ended|\(previousWait.rawValue)|\(Self.timestampKey(now))",
                    occurredAt: now,
                    mediaTime: snapshot.playback.currentTime,
                    kind: .waitEnded,
                    level: .observation,
                    title: "\(Self.waitTitle(previousWait)) ended",
                    measurement: snapshot.monitor?.waiting.lastWaitDuration.map(Self.seconds)
                )
            }
        }
    }

    private mutating func recordHealthEvents(
        _ events: [PlaybackHealthEvent],
        requestEntries: [PlaybackHealthRequestTraceEntry],
        latestStallAt: Date?
    ) {
        let orderedEvents = events.sorted {
            if $0.occurredAt == $1.occurredAt {
                return Self.healthEventKey($0) < Self.healthEventKey($1)
            }
            return $0.occurredAt < $1.occurredAt
        }
        for event in orderedEvents {
            if Self.requestTraceRepresents(event, entries: requestEntries) {
                continue
            }
            if event.signalKind == .playbackStall,
               let latestStallAt,
               abs(latestStallAt.timeIntervalSince(event.occurredAt)) <= 2 {
                continue
            }
            let key = [
                "health",
                event.signalKind.rawValue,
                event.mediaType.rawValue,
                Self.timestampKey(event.occurredAt),
                event.errorCode.map(String.init) ?? "none"
            ].joined(separator: "|")
            let kind: PlaybackDiagnosticsEvidenceKind
            let level: PlaybackDiagnosticsLevel
            let title: String
            switch event.signalKind {
            case .playlistRequestFailure:
                kind = .failedPlaylistRequest
                level = .warning
                title = "Playlist request failed"
            case .mediaSegmentRequestFailure:
                kind = .failedSegmentRequest
                level = .warning
                title = "Media segment request failed"
            case .contentKeyRequestFailure:
                kind = .failedContentKeyRequest
                level = .critical
                title = "Content-key request failed"
            case .errorLogEntry:
                kind = .errorLogEntry
                level = .notice
                title = "AVFoundation error-log signal"
            case .playbackStall:
                kind = .confirmedStall
                level = .warning
                title = "Playback stall confirmed"
            }
            let measurement = [event.errorDomain, event.errorCode.map(String.init)]
                .compactMap { $0 }
                .joined(separator: " / ")
            _ = appendEvidence(
                key: key,
                occurredAt: event.occurredAt,
                mediaTime: event.mediaTime,
                kind: kind,
                level: level,
                title: title,
                measurement: measurement.isEmpty ? nil : measurement
            )
        }
    }

    private mutating func recordRequestEvidence(_ snapshot: PlaybackDiagnosticsSnapshot) {
        guard let requestTrace = snapshot.monitor?.requestTrace else { return }
        let previousCount = cursor?.requestTraceReceivedCount ?? 0
        let addedCount = max(requestTrace.receivedCount - previousCount, 0)
        guard addedCount > 0 else { return }

        let retainedNewCount = min(addedCount, requestTrace.entries.count)
        let firstOrdinal = requestTrace.receivedCount - retainedNewCount
        let newEntries = Array(requestTrace.entries.suffix(retainedNewCount))
            .enumerated()
            .map { (ordinal: firstOrdinal + $0.offset, entry: $0.element) }
            .sorted {
                if $0.entry.occurredAt == $1.entry.occurredAt {
                    return $0.ordinal < $1.ordinal
                }
                return $0.entry.occurredAt < $1.entry.occurredAt
            }
        for newEntry in newEntries {
            let entry = newEntry.entry
            let prefix = [
                "request",
                String(newEntry.ordinal),
                entry.kind.rawValue,
                entry.mediaType.rawValue,
                Self.timestampKey(entry.occurredAt)
            ].joined(separator: "|")
            let failedKind: PlaybackDiagnosticsEvidenceKind
            switch entry.kind {
            case .playlist:
                failedKind = .failedPlaylistRequest
            case .segment:
                failedKind = .failedSegmentRequest
            case .contentKey:
                failedKind = .failedContentKeyRequest
            }

            if entry.didFail {
                let title: String
                switch entry.kind {
                case .playlist:
                    title = "Playlist request failed"
                case .segment:
                    title = "Media segment request failed"
                case .contentKey:
                    title = "Content-key request failed"
                }
                _ = appendEvidence(
                    key: "\(prefix)|failure",
                    occurredAt: entry.occurredAt,
                    mediaTime: nil,
                    kind: failedKind,
                    level: entry.kind == .contentKey ? .critical : .warning,
                    title: title,
                    measurement: Self.requestMeasurement(entry)
                )
            }

            if entry.kind == .segment,
               let ratio = entry.segmentDeliveryRatio,
               ratio.isFinite,
               ratio > 1 {
                _ = appendEvidence(
                    key: "\(prefix)|slow",
                    occurredAt: entry.occurredAt,
                    mediaTime: nil,
                    kind: .slowSegment,
                    level: .notice,
                    title: "Segment delivery exceeded media duration",
                    measurement: String(
                        format: "%.2f× segment duration",
                        locale: Self.posixLocale,
                        ratio
                    )
                )
            }

            if (entry.kind == .playlist || entry.kind == .segment),
               entry.mimeCategory == .html || entry.mimeCategory == .json {
                let evidenceID = appendEvidence(
                    key: "\(prefix)|mime",
                    occurredAt: entry.occurredAt,
                    mediaTime: nil,
                    kind: .unexpectedMediaResponse,
                    level: .warning,
                    title: "Unexpected media response type",
                    measurement: entry.mimeCategory?.rawValue
                )
                if let evidenceID {
                    appendPointIncident(
                        kind: .unexpectedMediaResponse,
                        severity: .warning,
                        at: entry.occurredAt,
                        impact: "The response did not identify as expected HLS media.",
                        likelyCause: "The playlist or segment request returned HTML or JSON. The retained evidence does not identify the server or route.",
                        evidenceID: evidenceID,
                        measuredValues: [entry.mimeCategory?.rawValue].compactMap { $0 },
                        nextAction: "Inspect the corresponding sanitized request timing and HTTP status in Technical Evidence.",
                        strength: .direct
                    )
                }
            }
        }
    }

    private mutating func recordFallbackTerminalFailure(
        _ snapshot: PlaybackDiagnosticsSnapshot,
        at now: Date
    ) {
        guard snapshot.playback.itemStatus == "failed",
              snapshot.monitor?.terminalFailure == nil else {
            return
        }
        let error = snapshot.recentErrors.last
        let occurredAt = error?.occurredAt.flatMap(Self.finiteDate) ?? now
        let measurement = error.map {
            "\($0.domain ?? "Unlisted domain") / \($0.code)"
        } ?? "Error details unavailable"
        let evidenceID = appendEvidence(
            key: "terminal|fallback",
            occurredAt: occurredAt,
            mediaTime: snapshot.playback.currentTime,
            kind: .terminalFailure,
            level: .critical,
            title: "Playback item failed",
            measurement: measurement
        )
        guard let evidenceID else { return }
        openOrUpdateIncident(
            kind: .terminalFailure,
            severity: .critical,
            startedAt: occurredAt,
            observedAt: occurredAt,
            impact: "Playback terminated before a natural end.",
            likelyCause: error == nil
                ? "AVFoundation marked the item failed, but no sanitized error detail was measured."
                : "AVFoundation marked the item failed; the sanitized error domain and code are the available cause evidence.",
            evidenceIDs: [evidenceID],
            measuredValues: [measurement],
            nextAction: "Copy the privacy-safe report and compare another title to separate item-specific from device-wide failure.",
            strength: error == nil ? .limited : .direct
        )
        end(at: occurredAt)
    }

    private mutating func recordMonitorEvidence(_ snapshot: PlaybackDiagnosticsSnapshot) {
        guard let monitor = snapshot.monitor else { return }
        let previous = cursor

        if monitor.stallCount > (previous?.stallCount ?? 0),
           monitor.waiting.currentKind != .initial,
           monitor.waiting.currentKind != .seek,
           snapshot.playback.timeControlStatus != "paused" {
            let occurredAt = monitor.latestStallAt ?? snapshot.session.capturedAt
            let evidenceID = appendEvidence(
                key: "stall|\(Self.timestampKey(occurredAt))",
                occurredAt: occurredAt,
                mediaTime: snapshot.playback.currentTime,
                kind: .confirmedStall,
                level: .warning,
                title: "Playback stall confirmed",
                measurement: snapshot.playback.bufferHeadroom.map {
                    "Buffer headroom \(Self.seconds($0))"
                }
            )
            if let evidenceID {
                openOrUpdateIncident(
                    kind: .confirmedRebuffer,
                    severity: .warning,
                    startedAt: occurredAt,
                    observedAt: occurredAt,
                    impact: "Playback stopped advancing during the session.",
                    likelyCause: "AVFoundation confirmed a stall. Delivery evidence may narrow the cause, but a stall alone does not identify the network or CDN.",
                    evidenceIDs: [evidenceID],
                    measuredValues: snapshot.playback.bufferHeadroom.map {
                        ["Buffer headroom \(Self.seconds($0))"]
                    } ?? [],
                    nextAction: "Compare the stall range with buffer, request failures, and segment delivery in the shared timeline.",
                    strength: .direct
                )
            }
        }

        if let initial = monitor.likelyToKeepUp.initial,
           initial.occurredAt != previous?.likelyToKeepUpInitialAt,
           let timeTaken = initial.timeTaken,
           timeTaken.isFinite,
           timeTaken >= 5 {
            let evidenceID = appendEvidence(
                key: "startup|\(Self.timestampKey(initial.occurredAt))",
                occurredAt: initial.occurredAt,
                mediaTime: initial.mediaTime,
                kind: .playbackReady,
                level: .notice,
                title: "Startup reached likely-to-keep-up",
                measurement: Self.seconds(timeTaken)
            )
            if let evidenceID {
                appendPointIncident(
                    kind: .slowStartup,
                    severity: .notice,
                    startedAt: initial.occurredAt.addingTimeInterval(-timeTaken),
                    endedAt: initial.occurredAt,
                    impact: "Playback took longer than five seconds to become likely to keep up.",
                    likelyCause: "Startup delay was measured, but the available evidence does not prove whether media delivery, content-key delivery, or local preparation dominated it.",
                    evidenceID: evidenceID,
                    measuredValues: ["Startup \(Self.seconds(timeTaken))"],
                    nextAction: "Inspect initial playlist, segment, and content-key timings in Technical Evidence.",
                    strength: .direct
                )
            }
        }

        if monitor.contentKeys.failedCount > (previous?.failedContentKeyCount ?? 0) {
            let evidence = storyboard.evidence.last {
                $0.kind == .failedContentKeyRequest
            }
            let occurredAt = evidence?.occurredAt
                ?? monitor.latestFailureContext?.occurredAt
                ?? snapshot.session.capturedAt
            let evidenceID = evidence?.id ?? appendEvidence(
                key: "key-failure|\(Self.timestampKey(occurredAt))",
                occurredAt: occurredAt,
                mediaTime: snapshot.playback.currentTime,
                kind: .failedContentKeyRequest,
                level: .critical,
                title: "Content-key request failed",
                measurement: nil
            )
            if let evidenceID {
                openOrUpdateIncident(
                    kind: .contentKeyFailure,
                    severity: .critical,
                    startedAt: occurredAt,
                    observedAt: occurredAt,
                    impact: "Protected media may be unable to start or continue.",
                    likelyCause: "A typed content-key request carried failure evidence. No key identifier or request URL is retained.",
                    evidenceIDs: [evidenceID],
                    measuredValues: ["Failed content-key requests \(monitor.contentKeys.failedCount)"],
                    nextAction: "Check license-service availability and the sanitized domain/code in Technical Evidence.",
                    strength: .direct
                )
            }
        }

        recordVariantTransitionEvidence(
            monitor.variantSwitches,
            previousCount: previous?.variantSwitchCount ?? 0,
            mediaTime: snapshot.playback.currentTime
        )

        if let dropped = snapshot.network.droppedVideoFrameCount,
           let previousDropped = previous?.droppedFrameCount,
           dropped > previousDropped {
            let delta = dropped - previousDropped
            droppedFrameBurst += delta
            let evidenceID = appendEvidence(
                key: "frames|\(Self.timestampKey(snapshot.session.capturedAt))|\(dropped)",
                occurredAt: snapshot.session.capturedAt,
                mediaTime: snapshot.playback.currentTime,
                kind: .droppedFrames,
                level: droppedFrameBurst >= 5 ? .warning : .notice,
                title: "Dropped video frames increased",
                measurement: "\(delta) new, \(dropped) total"
            )
            if droppedFrameBurst >= 5, let evidenceID {
                openOrUpdateIncident(
                    kind: .renderPressure,
                    severity: .warning,
                    startedAt: snapshot.session.capturedAt,
                    observedAt: snapshot.session.capturedAt,
                    impact: "Video frames were dropped during playback.",
                    likelyCause: "Dropped frames indicate render pressure; the measurement does not distinguish decoder, GPU, or system load.",
                    evidenceIDs: [evidenceID],
                    measuredValues: ["\(delta) newly dropped frames"],
                    nextAction: "Compare rendition resolution and frame rate, then inspect device load outside the player.",
                    strength: .direct
                )
            }
        } else {
            droppedFrameBurst = 0
        }

        if let failure = monitor.terminalFailure,
           failure.occurredAt != previous?.terminalFailureAt {
            let evidenceID = appendEvidence(
                key: "terminal|\(Self.timestampKey(failure.occurredAt))",
                occurredAt: failure.occurredAt,
                mediaTime: failure.mediaTime,
                kind: .terminalFailure,
                level: .critical,
                title: "Playback failed before the end",
                measurement: "\(failure.error.domain ?? "Unlisted domain") / \(failure.error.code)"
            )
            if let evidenceID {
                openOrUpdateIncident(
                    kind: .terminalFailure,
                    severity: .critical,
                    startedAt: failure.occurredAt,
                    observedAt: failure.occurredAt,
                    impact: "Playback terminated before a natural end.",
                    likelyCause: "AVFoundation reported a terminal failure. The sanitized domain and code are the available cause evidence.",
                    evidenceIDs: [evidenceID],
                    measuredValues: ["\(failure.error.domain ?? "Unlisted domain") / \(failure.error.code)"],
                    nextAction: "Copy the privacy-safe report and compare another title to separate item-specific from device-wide failure.",
                    strength: .direct
                )
            }
            end(at: failure.occurredAt)
        }

        if let naturalEnd = monitor.naturalEnd,
           naturalEnd.occurredAt != previous?.naturalEndAt {
            _ = appendEvidence(
                key: "natural-end|\(Self.timestampKey(naturalEnd.occurredAt))",
                occurredAt: naturalEnd.occurredAt,
                mediaTime: naturalEnd.mediaTime,
                kind: .naturalEnd,
                level: .observation,
                title: "Playback ended naturally",
                measurement: nil
            )
            end(at: naturalEnd.occurredAt)
        }
    }

    private mutating func recordVariantTransitionEvidence(
        _ switches: PlaybackHealthVariantSwitchTelemetry,
        previousCount: Int,
        mediaTime: Double?
    ) {
        let addedCount = max(switches.totalCount - previousCount, 0)
        let retainedNewCount = min(addedCount, switches.recentTransitions.count)
        guard retainedNewCount > 0 else { return }

        let firstOrdinal = switches.totalCount - retainedNewCount
        let transitions = Array(switches.recentTransitions.suffix(retainedNewCount))
            .enumerated()
            .map { (ordinal: firstOrdinal + $0.offset, transition: $0.element) }
            .sorted {
                if $0.transition.occurredAt == $1.transition.occurredAt {
                    return $0.ordinal < $1.ordinal
                }
                return $0.transition.occurredAt < $1.transition.occurredAt
            }

        for item in transitions {
            _ = appendEvidence(
                key: [
                    "variant",
                    String(item.ordinal),
                    Self.timestampKey(item.transition.occurredAt)
                ].joined(separator: "|"),
                occurredAt: item.transition.occurredAt,
                mediaTime: mediaTime,
                kind: .variantSwitch,
                level: item.transition.succeeded ? .observation : .notice,
                title: item.transition.succeeded
                    ? "Rendition switch observed"
                    : "Rendition switch did not complete",
                measurement: Self.variantMeasurement(item.transition)
            )
        }
    }

    private mutating func reduceIncidents(
        _ snapshot: PlaybackDiagnosticsSnapshot,
        at now: Date
    ) {
        let waitKind = snapshot.monitor?.waiting.currentKind
        let excludesDeliveryIncident = waitKind == .initial
            || waitKind == .seek
            || snapshot.playback.timeControlStatus == "paused"
        let lowBuffer = snapshot.playback.bufferHeadroom.map { $0 <= 2 } == true
        let deliveryPressure = Self.deliveryPressure(snapshot)

        if snapshot.playback.itemStatus == "ready",
           !excludesDeliveryIncident,
           lowBuffer,
           deliveryPressure {
            if lowBufferStartedAt == nil {
                lowBufferStartedAt = now
                lowBufferSampleCount = 1
            } else {
                lowBufferSampleCount += 1
            }
        } else {
            resetLowBufferCandidate()
        }

        if let lowBufferStartedAt,
           lowBufferSampleCount >= Self.candidateSampleCount,
           now.timeIntervalSince(lowBufferStartedAt) >= Self.candidateDuration {
            var evidenceIDs = recentEvidence(
                kinds: [.slowSegment, .failedSegmentRequest, .failedPlaylistRequest],
                at: now,
                within: 10
            ).map(\.id)
            if activeIncident(.deliveryStarvation) == nil {
                let pressureID = appendEvidence(
                    key: "delivery-pressure|\(Self.timestampKey(lowBufferStartedAt))",
                    occurredAt: now,
                    mediaTime: snapshot.playback.currentTime,
                    kind: .deliveryPressure,
                    level: .warning,
                    title: "Sustained low buffer with delivery pressure",
                    measurement: Self.deliveryMeasurements(snapshot)
                        .joined(separator: " · ")
                )
                if let pressureID {
                    evidenceIDs.append(pressureID)
                }
            }
            openOrUpdateIncident(
                kind: .deliveryStarvation,
                severity: .warning,
                startedAt: lowBufferStartedAt,
                observedAt: now,
                impact: "Buffer headroom stayed low while measured delivery evidence showed pressure.",
                likelyCause: "Delivery starvation is likely from correlated buffer and request or bitrate evidence; observed bitrate is a delivery proxy, not connection capacity.",
                evidenceIDs: evidenceIDs,
                measuredValues: Self.deliveryMeasurements(snapshot),
                nextAction: "Inspect failed or slow requests in Technical Evidence and compare observed versus indicated bitrate over the incident range.",
                strength: .correlated
            )
        }

        let healthyRecovery = snapshot.playback.itemStatus == "ready"
            && snapshot.playback.timeControlStatus == "playing"
            && waitKind == nil
            && snapshot.playback.isPlaybackLikelyToKeepUp
            && snapshot.playback.bufferHeadroom.map { $0 >= 5 } == true
        let hasRecoverableIncident = activeIncident(.deliveryStarvation) != nil
            || activeIncident(.confirmedRebuffer) != nil
        if healthyRecovery, hasRecoverableIncident {
            if healthyRecoveryStartedAt == nil {
                healthyRecoveryStartedAt = now
                healthyRecoverySampleCount = 1
            } else {
                healthyRecoverySampleCount += 1
            }
        } else {
            resetHealthyRecoveryCandidate()
        }

        if let healthyRecoveryStartedAt,
           healthyRecoverySampleCount >= Self.candidateSampleCount,
           now.timeIntervalSince(healthyRecoveryStartedAt) >= Self.candidateDuration {
            closeIncident(.deliveryStarvation, at: now, mediaTime: snapshot.playback.currentTime)
            closeIncident(.confirmedRebuffer, at: now, mediaTime: snapshot.playback.currentTime)
            resetHealthyRecoveryCandidate()
        }

        let requestFailures = recentEvidence(
            kinds: [.failedPlaylistRequest, .failedSegmentRequest],
            at: now,
            within: Self.correlationWindow
        )
        if requestFailures.count >= 3 {
            openOrUpdateIncident(
                kind: .repeatedRequestFailures,
                severity: .warning,
                startedAt: requestFailures.first?.occurredAt ?? now,
                observedAt: requestFailures.last?.occurredAt ?? now,
                impact: "Multiple playlist or segment requests failed within thirty seconds.",
                likelyCause: "Repeated delivery failures were measured, but retained evidence does not identify an ISP, CDN region, or server.",
                evidenceIDs: requestFailures.map(\.id),
                measuredValues: ["\(requestFailures.count) failures in 30 seconds"],
                nextAction: "Inspect the sanitized status, timing, and media type for the correlated requests.",
                strength: .direct
            )
        } else if let incident = activeIncident(.repeatedRequestFailures),
                  now.timeIntervalSince(incident.lastObservedAt) >= 15,
                  snapshot.playback.timeControlStatus == "playing" {
            closeIncident(.repeatedRequestFailures, at: now, mediaTime: snapshot.playback.currentTime)
        }

        let recentTransitions = (snapshot.monitor?.variantSwitches.recentTransitions ?? [])
            .filter {
                $0.succeeded
                    && now >= $0.occurredAt
                    && now.timeIntervalSince($0.occurredAt) <= Self.correlationWindow
            }
            .sorted { $0.occurredAt < $1.occurredAt }
        let transitionEvidence = recentEvidence(
            kinds: [.variantSwitch],
            at: now,
            within: Self.correlationWindow
        )
        let downTransitions = recentTransitions.filter {
            Self.variantDirection($0) == .down
        }
        if downTransitions.count >= 2 {
            openOrUpdateIncident(
                kind: .renditionDowngrade,
                severity: .notice,
                startedAt: downTransitions.first?.occurredAt ?? now,
                observedAt: downTransitions.last?.occurredAt ?? now,
                impact: "AVFoundation selected lower-bitrate renditions repeatedly.",
                likelyCause: "Repeated measured downgrades may reflect delivery or playback pressure, but the transitions alone do not prove either cause.",
                evidenceIDs: transitionEvidenceIDs(
                    for: downTransitions,
                    from: transitionEvidence
                ),
                measuredValues: ["\(downTransitions.count) downgrades in 30 seconds"],
                nextAction: "Compare the switches with observed delivery, buffer headroom, and request evidence.",
                strength: .correlated
            )
        } else if let incident = activeIncident(.renditionDowngrade),
                  now.timeIntervalSince(incident.lastObservedAt) >= 20 {
            closeIncident(.renditionDowngrade, at: now, mediaTime: snapshot.playback.currentTime)
        }

        let directedTransitions = recentTransitions.filter {
            Self.variantDirection($0) == .up || Self.variantDirection($0) == .down
        }
        if directedTransitions.count >= 4,
           Self.directionChangeCount(directedTransitions) >= 2 {
            openOrUpdateIncident(
                kind: .abrThrashing,
                severity: .notice,
                startedAt: directedTransitions.first?.occurredAt ?? now,
                observedAt: directedTransitions.last?.occurredAt ?? now,
                impact: "The selected rendition changed repeatedly.",
                likelyCause: "Frequent adaptive switches were measured. The evidence does not prove whether delivery variability or local playback constraints caused them.",
                evidenceIDs: transitionEvidenceIDs(
                    for: directedTransitions,
                    from: transitionEvidence
                ),
                measuredValues: ["\(directedTransitions.count) directed switches in 30 seconds"],
                nextAction: "Compare buffer and delivery lanes, then inspect the measured from/to renditions.",
                strength: .direct
            )
        } else if let incident = activeIncident(.abrThrashing),
                  now.timeIntervalSince(incident.lastObservedAt) >= 20 {
            closeIncident(.abrThrashing, at: now, mediaTime: snapshot.playback.currentTime)
        }

        for kind in [
            PlaybackDiagnosticsIncidentKind.contentKeyFailure,
            .renderPressure
        ] {
            if let incident = activeIncident(kind),
               now.timeIntervalSince(incident.lastObservedAt) >= 10,
               snapshot.playback.timeControlStatus == "playing" {
                closeIncident(kind, at: now, mediaTime: snapshot.playback.currentTime)
            }
        }
    }

    @discardableResult
    private mutating func appendEvidence(
        key: String,
        occurredAt: Date,
        mediaTime: Double?,
        kind: PlaybackDiagnosticsEvidenceKind,
        level: PlaybackDiagnosticsLevel,
        title: String,
        measurement: String?
    ) -> UUID? {
        guard Self.isFinite(occurredAt), rememberEvidenceKey(key) else {
            return nil
        }
        let evidence = PlaybackDiagnosticsEvidence(
            id: stableID("evidence|\(key)"),
            occurredAt: occurredAt,
            mediaTime: Self.nonnegative(mediaTime),
            kind: kind,
            level: level,
            title: title,
            measurement: measurement
        )
        storyboard.evidence.append(evidence)
        storyboard.evidence.sort(by: Self.evidencePrecedes)
        while storyboard.evidence.count > Self.evidenceCapacity {
            let protectedIDs = Set(
                storyboard.incidents
                    .filter { $0.state == .active }
                    .flatMap(\.evidenceIDs)
            )
            let unprotected = storyboard.evidence.indices.filter {
                !protectedIDs.contains(storyboard.evidence[$0].id)
            }
            let candidates = unprotected.isEmpty
                ? Array(storyboard.evidence.indices)
                : unprotected
            guard let index = candidates.min(by: {
                let lhs = storyboard.evidence[$0]
                let rhs = storyboard.evidence[$1]
                if lhs.level == rhs.level {
                    return Self.evidencePrecedes(lhs, rhs)
                }
                return lhs.level < rhs.level
            }) else {
                break
            }
            storyboard.evidence.remove(at: index)
        }
        pruneEvidenceReferences()
        return evidence.id
    }

    private mutating func rememberEvidenceKey(_ key: String) -> Bool {
        guard seenEvidenceKeys.insert(key).inserted else { return false }
        seenEvidenceKeyOrder.append(key)
        // ponytail: 240 small keys bound reducer deduplication; use a deque if
        // retention grows beyond the five-minute session window.
        if seenEvidenceKeyOrder.count > Self.evidenceCapacity * 2 {
            let overflow = seenEvidenceKeyOrder.count - Self.evidenceCapacity * 2
            let removed = seenEvidenceKeyOrder.prefix(overflow)
            seenEvidenceKeys.subtract(removed)
            seenEvidenceKeyOrder.removeFirst(overflow)
        }
        return true
    }

    private mutating func openOrUpdateIncident(
        kind: PlaybackDiagnosticsIncidentKind,
        severity: PlaybackDiagnosticsLevel,
        startedAt: Date,
        observedAt: Date,
        impact: String,
        likelyCause: String,
        evidenceIDs: [UUID],
        measuredValues: [String],
        nextAction: String,
        strength: PlaybackDiagnosticsEvidenceStrength
    ) {
        var incidents = storyboard.incidents
        let normalizedStart = min(startedAt, observedAt)
        let retainedEvidenceIDs = retainedEvidenceIDs(evidenceIDs)
        if let index = incidents.lastIndex(where: {
            $0.kind == kind && $0.state == .active
        }) {
            incidents[index].lastObservedAt = max(incidents[index].lastObservedAt, observedAt)
            incidents[index].evidenceIDs = Self.boundedMerge(
                incidents[index].evidenceIDs,
                retainedEvidenceIDs,
                capacity: Self.incidentEvidenceCapacity
            )
            incidents[index].measuredValues = Self.boundedMerge(
                incidents[index].measuredValues,
                measuredValues,
                capacity: Self.incidentMeasurementCapacity
            )
        } else {
            let seed = retainedEvidenceIDs.first?.uuidString ?? "none"
            incidents.append(
                PlaybackDiagnosticsAutomaticIncident(
                    id: stableID(
                        "incident|\(kind.rawValue)|\(Self.timestampKey(normalizedStart))|\(seed)"
                    ),
                    kind: kind,
                    severity: severity,
                    startedAt: normalizedStart,
                    lastObservedAt: observedAt,
                    endedAt: nil,
                    impact: impact,
                    likelyCause: likelyCause,
                    evidenceIDs: Array(
                        retainedEvidenceIDs.suffix(Self.incidentEvidenceCapacity)
                    ),
                    measuredValues: Array(
                        Self.unique(measuredValues)
                            .suffix(Self.incidentMeasurementCapacity)
                    ),
                    nextAction: nextAction,
                    evidenceStrength: strength
                )
            )
        }
        retainIncidents(&incidents)
    }

    private mutating func appendPointIncident(
        kind: PlaybackDiagnosticsIncidentKind,
        severity: PlaybackDiagnosticsLevel,
        at occurredAt: Date,
        impact: String,
        likelyCause: String,
        evidenceID: UUID,
        measuredValues: [String],
        nextAction: String,
        strength: PlaybackDiagnosticsEvidenceStrength
    ) {
        appendPointIncident(
            kind: kind,
            severity: severity,
            startedAt: occurredAt,
            endedAt: occurredAt,
            impact: impact,
            likelyCause: likelyCause,
            evidenceID: evidenceID,
            measuredValues: measuredValues,
            nextAction: nextAction,
            strength: strength
        )
    }

    private mutating func appendPointIncident(
        kind: PlaybackDiagnosticsIncidentKind,
        severity: PlaybackDiagnosticsLevel,
        startedAt: Date,
        endedAt: Date,
        impact: String,
        likelyCause: String,
        evidenceID: UUID,
        measuredValues: [String],
        nextAction: String,
        strength: PlaybackDiagnosticsEvidenceStrength
    ) {
        var incidents = storyboard.incidents
        if let index = incidents.lastIndex(where: {
            guard $0.kind == kind, $0.endedAt != nil else { return false }
            let interval = endedAt.timeIntervalSince($0.lastObservedAt)
            return interval >= 0 && interval <= Self.correlationWindow
        }) {
            incidents[index].lastObservedAt = max(
                incidents[index].lastObservedAt,
                endedAt
            )
            incidents[index].endedAt = max(
                incidents[index].endedAt ?? endedAt,
                endedAt
            )
            incidents[index].evidenceIDs = Self.boundedMerge(
                incidents[index].evidenceIDs,
                retainedEvidenceIDs([evidenceID]),
                capacity: Self.incidentEvidenceCapacity
            )
            incidents[index].measuredValues = Self.boundedMerge(
                incidents[index].measuredValues,
                measuredValues,
                capacity: Self.incidentMeasurementCapacity
            )
        } else {
            incidents.append(
                PlaybackDiagnosticsAutomaticIncident(
                    id: stableID(
                        "incident|\(kind.rawValue)|\(Self.timestampKey(startedAt))|\(evidenceID.uuidString)"
                    ),
                    kind: kind,
                    severity: severity,
                    startedAt: min(startedAt, endedAt),
                    lastObservedAt: endedAt,
                    endedAt: endedAt,
                    impact: impact,
                    likelyCause: likelyCause,
                    evidenceIDs: retainedEvidenceIDs([evidenceID]),
                    measuredValues: Array(
                        Self.unique(measuredValues)
                            .suffix(Self.incidentMeasurementCapacity)
                    ),
                    nextAction: nextAction,
                    evidenceStrength: strength
                )
            )
        }
        retainIncidents(&incidents)
    }

    private mutating func closeIncident(
        _ kind: PlaybackDiagnosticsIncidentKind,
        at endedAt: Date,
        mediaTime: Double?
    ) {
        var incidents = storyboard.incidents
        guard let index = incidents.lastIndex(where: {
            $0.kind == kind && $0.state == .active
        }) else {
            return
        }
        let recoveryID = appendEvidence(
            key: "recovery|\(incidents[index].id.uuidString)",
            occurredAt: endedAt,
            mediaTime: mediaTime,
            kind: .recovery,
            level: .observation,
            title: "\(kind.title) recovered",
            measurement: nil
        )
        incidents = storyboard.incidents
        guard let refreshedIndex = incidents.lastIndex(where: {
            $0.kind == kind && $0.state == .active
        }) else {
            return
        }
        incidents[refreshedIndex].endedAt = max(
            endedAt,
            incidents[refreshedIndex].startedAt
        )
        if let recoveryID {
            incidents[refreshedIndex].evidenceIDs = Self.boundedMerge(
                incidents[refreshedIndex].evidenceIDs,
                [recoveryID],
                capacity: Self.incidentEvidenceCapacity
            )
        }
        storyboard.incidents = incidents
    }

    private func activeIncident(
        _ kind: PlaybackDiagnosticsIncidentKind
    ) -> PlaybackDiagnosticsAutomaticIncident? {
        storyboard.incidents.last {
            $0.kind == kind && $0.state == .active
        }
    }

    private mutating func retainIncidents(
        _ incidents: inout [PlaybackDiagnosticsAutomaticIncident]
    ) {
        while incidents.count > Self.incidentCapacity {
            let index = incidents.firstIndex { $0.state == .recovered }
                ?? incidents.startIndex
            incidents.remove(at: index)
        }
        incidents.sort(by: Self.incidentPrecedes)
        storyboard.incidents = incidents
    }

    private mutating func updateSessionMilestones(
        _ snapshot: PlaybackDiagnosticsSnapshot,
        at now: Date
    ) {
        if storyboard.firstPlayingAt == nil,
           snapshot.playback.timeControlStatus == "playing" {
            storyboard.firstPlayingAt = now
        }

        if storyboard.firstLikelyToKeepUpAt == nil {
            let measured = Self.finiteDate(
                snapshot.monitor?.likelyToKeepUp.initial?.occurredAt
            )
            if let measured,
               measured <= now,
               measured >= (storyboard.sessionStartedAt ?? measured) {
                storyboard.firstLikelyToKeepUpAt = measured
            } else if snapshot.playback.isPlaybackLikelyToKeepUp {
                storyboard.firstLikelyToKeepUpAt = now
            }
        }
    }

    private mutating func resetLowBufferCandidate() {
        lowBufferStartedAt = nil
        lowBufferSampleCount = 0
    }

    private mutating func resetHealthyRecoveryCandidate() {
        healthyRecoveryStartedAt = nil
        healthyRecoverySampleCount = 0
    }

    private func sessionElapsed(at date: Date) -> TimeInterval? {
        guard let startedAt = storyboard.sessionStartedAt else { return nil }
        let elapsed = date.timeIntervalSince(startedAt)
        return elapsed.isFinite && elapsed >= 0 ? elapsed : nil
    }

    private func recentEvidence(
        kinds: Set<PlaybackDiagnosticsEvidenceKind>,
        at now: Date,
        within window: TimeInterval
    ) -> [PlaybackDiagnosticsEvidence] {
        storyboard.evidence.filter {
            kinds.contains($0.kind)
                && now >= $0.occurredAt
                && now.timeIntervalSince($0.occurredAt) <= window
        }
    }

    private func transitionEvidenceIDs(
        for transitions: [PlaybackHealthVariantTransition],
        from evidence: [PlaybackDiagnosticsEvidence]
    ) -> [UUID] {
        let timestamps = Set(transitions.map { Self.timestampKey($0.occurredAt) })
        return evidence
            .filter { timestamps.contains(Self.timestampKey($0.occurredAt)) }
            .map(\.id)
    }

    private func retainedEvidenceIDs(_ ids: [UUID]) -> [UUID] {
        let retained = Set(storyboard.evidence.map(\.id))
        return Self.unique(ids).filter(retained.contains)
    }

    private mutating func pruneEvidenceReferences() {
        let retained = Set(storyboard.evidence.map(\.id))
        for index in storyboard.incidents.indices {
            storyboard.incidents[index].evidenceIDs.removeAll {
                !retained.contains($0)
            }
        }
        for index in storyboard.bookmarks.indices {
            storyboard.bookmarks[index].nearbyEvidenceIDs.removeAll {
                !retained.contains($0)
            }
        }
    }

    private mutating func pruneBookmarkSampleReferences() {
        let retained = Set(storyboard.samples.map(\.id))
        for index in storyboard.bookmarks.indices {
            storyboard.bookmarks[index].nearbySampleIDs.removeAll {
                !retained.contains($0)
            }
        }
    }

    private func stableID(_ key: String) -> UUID {
        Self.stableUUID(
            [
                identity?.backend ?? "unknown-backend",
                identity?.sessionID?.uuidString ?? "no-session",
                identity?.assetIdentifier ?? "no-asset",
                identity?.startedAt.map(Self.timestampKey)
                    ?? storyboard.sessionStartedAt.map(Self.timestampKey)
                    ?? "no-start",
                key
            ].joined(separator: "|")
        )
    }

    private static func stableUUID(_ key: String) -> UUID {
        let bytes = Array(key.utf8)
        let first = fnv1a(bytes, seed: 0xcbf29ce484222325)
        let second = fnv1a(bytes.reversed(), seed: 0x84222325cbf29ce4)
        let hex = String(
            format: "%016llx%016llx",
            locale: posixLocale,
            first,
            second
        )
        let firstGroup = String(hex.prefix(8))
        let secondGroup = String(hex.dropFirst(8).prefix(4))
        let thirdGroup = String(hex.dropFirst(12).prefix(4))
        let fourthGroup = String(hex.dropFirst(16).prefix(4))
        let fifthGroup = String(hex.dropFirst(20).prefix(12))
        let value = [
            firstGroup,
            secondGroup,
            thirdGroup,
            fourthGroup,
            fifthGroup
        ].joined(separator: "-")
        return UUID(uuidString: value)!
    }

    private static func fnv1a<S: Sequence>(
        _ bytes: S,
        seed: UInt64
    ) -> UInt64 where S.Element == UInt8 {
        bytes.reduce(seed) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }

    private static func nearbyIDs(
        _ values: [(UUID, Date)],
        to capturedAt: Date
    ) -> [UUID] {
        values
            .filter { abs($0.1.timeIntervalSince(capturedAt)) <= 5 }
            .sorted {
                let lhsDistance = abs($0.1.timeIntervalSince(capturedAt))
                let rhsDistance = abs($1.1.timeIntervalSince(capturedAt))
                if lhsDistance == rhsDistance {
                    if $0.1 == $1.1 {
                        return $0.0.uuidString < $1.0.uuidString
                    }
                    return $0.1 < $1.1
                }
                return lhsDistance < rhsDistance
            }
            .prefix(bookmarkReferenceCapacity)
            .map(\.0)
    }

    private static func requestTraceRepresents(
        _ event: PlaybackHealthEvent,
        entries: [PlaybackHealthRequestTraceEntry]
    ) -> Bool {
        let kind: PlaybackHealthRequestKind
        switch event.signalKind {
        case .playlistRequestFailure:
            kind = .playlist
        case .mediaSegmentRequestFailure:
            kind = .segment
        case .contentKeyRequestFailure:
            kind = .contentKey
        case .errorLogEntry, .playbackStall:
            return false
        }
        return entries.contains {
            $0.didFail
                && $0.kind == kind
                && $0.mediaType == event.mediaType
                && abs($0.occurredAt.timeIntervalSince(event.occurredAt)) <= 2
        }
    }

    private static func healthEventKey(_ event: PlaybackHealthEvent) -> String {
        [
            event.signalKind.rawValue,
            event.mediaType.rawValue,
            timestampKey(event.occurredAt),
            event.errorCode.map(String.init) ?? "none"
        ].joined(separator: "|")
    }

    private static func evidencePrecedes(
        _ lhs: PlaybackDiagnosticsEvidence,
        _ rhs: PlaybackDiagnosticsEvidence
    ) -> Bool {
        if lhs.occurredAt == rhs.occurredAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.occurredAt < rhs.occurredAt
    }

    private static func incidentPrecedes(
        _ lhs: PlaybackDiagnosticsAutomaticIncident,
        _ rhs: PlaybackDiagnosticsAutomaticIncident
    ) -> Bool {
        if lhs.startedAt == rhs.startedAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.startedAt < rhs.startedAt
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func boundedMerge<T: Hashable>(
        _ existing: [T],
        _ additions: [T],
        capacity: Int
    ) -> [T] {
        Array(unique(existing + additions).suffix(capacity))
    }

    private static func variantDirection(
        _ transition: PlaybackHealthVariantTransition
    ) -> VariantDirection {
        guard transition.succeeded, let from = transition.from else {
            return .unknown
        }
        let fromBitRate = positive(from.averageBitRate) ?? positive(from.peakBitRate)
        let toBitRate = positive(transition.to.averageBitRate)
            ?? positive(transition.to.peakBitRate)
        if let fromBitRate, let toBitRate {
            if toBitRate > fromBitRate { return .up }
            if toBitRate < fromBitRate { return .down }
            return .lateral
        }
        if let fromPixels = resolutionPixels(from.resolution),
           let toPixels = resolutionPixels(transition.to.resolution) {
            if toPixels > fromPixels { return .up }
            if toPixels < fromPixels { return .down }
            return .lateral
        }
        return .unknown
    }

    private static func directionChangeCount(
        _ transitions: [PlaybackHealthVariantTransition]
    ) -> Int {
        let directions = transitions.map(variantDirection)
        return zip(directions, directions.dropFirst()).reduce(into: 0) {
            if $1.0 != $1.1 {
                $0 += 1
            }
        }
    }

    private static func resolutionPixels(_ value: String?) -> Int? {
        guard let value else { return nil }
        let parts = value
            .replacingOccurrences(of: "x", with: "×")
            .split(separator: "×")
        guard parts.count == 2,
              let width = Int(parts[0]),
              let height = Int(parts[1]),
              width > 0,
              height > 0 else {
            return nil
        }
        let result = width.multipliedReportingOverflow(by: height)
        return result.overflow ? nil : result.partialValue
    }

    private static func deliveryPressure(
        _ snapshot: PlaybackDiagnosticsSnapshot
    ) -> Bool {
        let bitratePressure: Bool
        if let observed = nonnegative(snapshot.network.observedBitRate),
           let indicated = nonnegative(snapshot.network.indicatedBitRate),
           observed > 0,
           indicated > 0 {
            bitratePressure = observed < indicated * 0.75
        } else {
            bitratePressure = false
        }

        let now = snapshot.session.capturedAt
        let recentSlowDelivery = snapshot.monitor?.slowDelivery.latestOccurredAt.map {
            now >= $0 && now.timeIntervalSince($0) <= 10
        } == true
        let recentFailedRequest = snapshot.monitor?.requestTrace.entries.contains {
            $0.didFail
                && now >= $0.occurredAt
                && now.timeIntervalSince($0.occurredAt) <= 10
        } == true
        return bitratePressure || recentSlowDelivery || recentFailedRequest
    }

    private static func deliveryMeasurements(
        _ snapshot: PlaybackDiagnosticsSnapshot
    ) -> [String] {
        var values: [String] = []
        if let buffer = nonnegative(snapshot.playback.bufferHeadroom) {
            values.append("Buffer headroom \(seconds(buffer))")
        }
        if let observed = nonnegative(snapshot.network.observedBitRate) {
            values.append("Observed delivery \(bitRate(observed))")
        }
        if let indicated = nonnegative(snapshot.network.indicatedBitRate) {
            values.append("Indicated bitrate \(bitRate(indicated))")
        }
        if let ratio = snapshot.monitor?.slowDelivery.worstRatio,
           ratio.isFinite,
           ratio > 0 {
            values.append(
                String(
                    format: "Slowest segment %.2f× media duration",
                    locale: posixLocale,
                    ratio
                )
            )
        }
        return values
    }

    private static func requestMeasurement(
        _ entry: PlaybackHealthRequestTraceEntry
    ) -> String? {
        var parts: [String] = []
        if let status = entry.httpStatusCode {
            parts.append("HTTP \(status)")
        }
        if let duration = nonnegative(entry.requestDuration) {
            parts.append(seconds(duration))
        }
        if let recovered = entry.didRecover {
            parts.append(recovered ? "reported recovered" : "recovery not reported")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func variantMeasurement(
        _ transition: PlaybackHealthVariantTransition
    ) -> String? {
        let from = transition.from?.resolution
            ?? transition.from?.averageBitRate.map(bitRate)
            ?? transition.from?.peakBitRate.map(bitRate)
        let to = transition.to.resolution
            ?? transition.to.averageBitRate.map(bitRate)
            ?? transition.to.peakBitRate.map(bitRate)
        guard from != nil || to != nil else { return nil }
        return "\(from ?? "Not measured") → \(to ?? "Not measured")"
    }

    private static func waitTitle(_ kind: PlaybackHealthWaitKind) -> String {
        switch kind {
        case .initial:
            return "Initial wait"
        case .postStart:
            return "Playback wait"
        case .seek:
            return "Seek wait"
        }
    }

    private static func nonnegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func nonnegative(_ value: Int?) -> Int? {
        guard let value, value >= 0 else { return nil }
        return value
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static func finiteDate(_ value: Date?) -> Date? {
        guard let value, isFinite(value) else { return nil }
        return value
    }

    private static func isFinite(_ value: Date) -> Bool {
        value.timeIntervalSinceReferenceDate.isFinite
    }

    private static func timestampKey(_ value: Date) -> String {
        String(
            format: "%.6f",
            locale: posixLocale,
            value.timeIntervalSinceReferenceDate
        )
    }

    private static func seconds(_ value: Double) -> String {
        String(format: "%.2f s", locale: posixLocale, value)
    }

    private static func bitRate(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(
                format: "%.2f Mbps",
                locale: posixLocale,
                value / 1_000_000
            )
        }
        if value >= 1_000 {
            return String(
                format: "%.0f Kbps",
                locale: posixLocale,
                value / 1_000
            )
        }
        return String(format: "%.0f bps", locale: posixLocale, value)
    }
}
#endif
