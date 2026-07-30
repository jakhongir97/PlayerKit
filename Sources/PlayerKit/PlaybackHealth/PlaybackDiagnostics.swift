#if os(macOS)
import Foundation

// ponytail: These ceilings reject corrupt or adversarial AVFoundation metadata.
// Raise them only when real playback hardware needs larger dimensions/rates.
private let playbackDiagnosticsMaximumDimension = 65_536.0
private let playbackDiagnosticsMaximumFrameRate = 1_000.0
private let playbackDiagnosticsMaximumPlaybackRate = 64.0

func sanitizedPlaybackDiagnosticsResolution(
    width: Double,
    height: Double
) -> String? {
    guard width.isFinite,
          height.isFinite,
          width > 0,
          height > 0,
          width <= playbackDiagnosticsMaximumDimension,
          height <= playbackDiagnosticsMaximumDimension else {
        return nil
    }
    return "\(Int(width.rounded()))×\(Int(height.rounded()))"
}

func sanitizedPlaybackDiagnosticsFrameRate(_ value: Double?) -> Double? {
    guard let value,
          value.isFinite,
          value > 0,
          value <= playbackDiagnosticsMaximumFrameRate else {
        return nil
    }
    return value
}

func sanitizedPlaybackDiagnosticsRate(_ value: Double?) -> Double? {
    guard let value,
          value.isFinite,
          abs(value) <= playbackDiagnosticsMaximumPlaybackRate else {
        return nil
    }
    return value
}

enum PlaybackDiagnosticsAvailability: String, Sendable {
    case startingAVMetrics
    case activeAVMetrics
    case failedAVMetrics
    case endedAVMetrics
    case activeErrorLogFallback
    case monitoringDisabled
    case monitorNotAttached
    case noPlayerItem
    case unsupportedBackend

    var title: String {
        switch self {
        case .startingAVMetrics:
            return "Starting · AVMetrics"
        case .activeAVMetrics:
            return "Active · AVMetrics"
        case .failedAVMetrics:
            return "Failed · AVMetrics"
        case .endedAVMetrics:
            return "Ended · AVMetrics"
        case .activeErrorLogFallback:
            return "Active · Error-log fallback"
        case .monitoringDisabled:
            return "Monitoring disabled"
        case .monitorNotAttached:
            return "Monitor not attached"
        case .noPlayerItem:
            return "No player item"
        case .unsupportedBackend:
            return "Unsupported backend"
        }
    }
}

enum PlaybackDiagnosticsLevel: Int, Comparable, Sendable {
    case observation
    case notice
    case warning
    case critical

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum PlaybackDiagnosticsIssueScope: String, Sendable {
    case active
    case historical
    case coverage
}

struct PlaybackDiagnosticsIssue: Identifiable, Equatable, Sendable {
    let id: String
    let level: PlaybackDiagnosticsLevel
    let scope: PlaybackDiagnosticsIssueScope
    let title: String
    let detail: String
    let recommendation: String?
}

struct PlaybackDiagnosticsTrack: Equatable, Sendable {
    let identifier: String?
    let name: String
    let languageCode: String?
    let isSelected: Bool
}

func retainedPlaybackDiagnosticsAudioTrack(
    _ track: PlaybackDiagnosticsTrack?
) -> PlaybackDiagnosticsTrack? {
    track.map {
        PlaybackDiagnosticsTrack(
            identifier: $0.identifier,
            name: "Selected audio track",
            languageCode: $0.languageCode,
            isSelected: $0.isSelected
        )
    }
}

struct PlaybackDiagnosticsError: Equatable, Sendable {
    let occurredAt: Date?
    let domain: String?
    let code: Int
}

enum PlaybackHealthMonitorStreamState: String, Equatable, Sendable {
    case starting
    case observing
    case fallbackObserving
    case failed
    case ended
}

enum PlaybackHealthFallbackReason: String, Equatable, Sendable {
    case legacyOS
    case metricsFailed
    case metricsEnded
}

struct PlaybackHealthClassifierTelemetry: Equatable, Sendable {
    let candidateCount: Int
    let emittedCount: Int
    let suppressedCount: Int
    let sampleCap: Int

    static let empty = Self(
        candidateCount: 0,
        emittedCount: 0,
        suppressedCount: 0,
        sampleCap: MacOSPlaybackHealthClassifier.calibrationSampleCap
    )

    var sampleCapReached: Bool {
        emittedCount >= sampleCap
    }
}

struct PlaybackHealthRequestFailureContext: Equatable, Sendable {
    let signalKind: PlaybackHealthSignalKind
    let mediaType: PlaybackHealthMediaType
    let occurredAt: Date
    let requestDuration: Double?
    let timeToFirstByte: Double?
    let responseDuration: Double?
    let wasReadFromCache: Bool?
    let segmentDuration: Double?
    let requestedByteRangeLength: Int?
    let responseBodyBytes: Int64?
    let httpStatusCode: Int?
    let redirectCount: Int?
    let networkProtocol: String?
    let dnsDuration: Double?
    let connectDuration: Double?
    let tlsDuration: Double?

    var byteCount: Int? {
        requestedByteRangeLength
    }

    init(
        signalKind: PlaybackHealthSignalKind,
        mediaType: PlaybackHealthMediaType,
        occurredAt: Date,
        requestDuration: Double?,
        timeToFirstByte: Double?,
        responseDuration: Double?,
        wasReadFromCache: Bool?,
        segmentDuration: Double?,
        requestedByteRangeLength: Int? = nil,
        responseBodyBytes: Int64? = nil,
        httpStatusCode: Int? = nil,
        redirectCount: Int? = nil,
        networkProtocol: String? = nil,
        dnsDuration: Double? = nil,
        connectDuration: Double? = nil,
        tlsDuration: Double? = nil,
        byteCount: Int? = nil
    ) {
        self.signalKind = signalKind
        self.mediaType = mediaType
        self.occurredAt = occurredAt
        self.requestDuration = requestDuration
        self.timeToFirstByte = timeToFirstByte
        self.responseDuration = responseDuration
        self.wasReadFromCache = wasReadFromCache
        self.segmentDuration = segmentDuration
        self.requestedByteRangeLength = requestedByteRangeLength ?? byteCount
        self.responseBodyBytes = responseBodyBytes
        self.httpStatusCode = httpStatusCode
        self.redirectCount = redirectCount
        self.networkProtocol = networkProtocol
        self.dnsDuration = dnsDuration
        self.connectDuration = connectDuration
        self.tlsDuration = tlsDuration
    }
}

enum PlaybackHealthRequestKind: String, Equatable, Sendable {
    case playlist
    case segment
    case contentKey
}

enum PlaybackHealthMIMECategory: String, Equatable, Sendable {
    case hlsPlaylist
    case transportStream
    case mp4
    case html
    case json
    case text
    case binary
    case other
}

enum PlaybackHealthResourceFetchType: String, Equatable, Sendable {
    case unknown
    case networkLoad
    case serverPush
    case localCache
}

struct PlaybackHealthRequestTraceEntry: Equatable, Sendable {
    let kind: PlaybackHealthRequestKind
    let mediaType: PlaybackHealthMediaType
    let occurredAt: Date
    let didFail: Bool
    let didRecover: Bool?
    let requestDuration: Double?
    let timeToFirstByte: Double?
    let transferDuration: Double?
    let httpStatusCode: Int?
    let mimeCategory: PlaybackHealthMIMECategory?
    let wasReadFromCache: Bool?
    let redirectCount: Int?
    let networkProtocol: String?
    let responseBodyBytes: Int64?
    let decodedBodyBytes: Int64?
    let reusedConnection: Bool?
    let proxyConnection: Bool?
    let constrainedNetwork: Bool?
    let expensiveNetwork: Bool?
    let cellularNetwork: Bool?
    let multipathConnection: Bool?
    let fetchType: PlaybackHealthResourceFetchType?
    let segmentDeliveryRatio: Double?
}

struct PlaybackHealthRequestTraceTelemetry: Equatable, Sendable {
    static let capacity = 50

    private(set) var receivedCount = 0
    private(set) var droppedCount = 0
    private(set) var entries: [PlaybackHealthRequestTraceEntry] = []

    mutating func record(_ entry: PlaybackHealthRequestTraceEntry) {
        receivedCount += 1
        entries.append(entry)
        guard entries.count > Self.capacity else { return }
        let overflow = entries.count - Self.capacity
        entries.removeFirst(overflow)
        droppedCount += overflow
    }
}

struct PlaybackHealthContentKeyMediaTelemetry: Equatable, Sendable {
    var totalCount = 0
    var succeededCount = 0
    var failedCount = 0
    var clientInitiatedCount = 0

    mutating func record(failed: Bool, clientInitiated: Bool) {
        totalCount += 1
        if failed {
            failedCount += 1
        } else {
            succeededCount += 1
        }
        if clientInitiated {
            clientInitiatedCount += 1
        }
    }
}

struct PlaybackHealthContentKeyTelemetry: Equatable, Sendable {
    var audio = PlaybackHealthContentKeyMediaTelemetry()
    var video = PlaybackHealthContentKeyMediaTelemetry()
    var muxed = PlaybackHealthContentKeyMediaTelemetry()
    var unknown = PlaybackHealthContentKeyMediaTelemetry()

    var totalCount: Int {
        buckets.map(\.totalCount).reduce(0, +)
    }

    var succeededCount: Int {
        buckets.map(\.succeededCount).reduce(0, +)
    }

    var failedCount: Int {
        buckets.map(\.failedCount).reduce(0, +)
    }

    var clientInitiatedCount: Int {
        buckets.map(\.clientInitiatedCount).reduce(0, +)
    }

    mutating func record(
        mediaType: PlaybackHealthMediaType,
        failed: Bool,
        clientInitiated: Bool
    ) {
        switch mediaType {
        case .audio:
            audio.record(failed: failed, clientInitiated: clientInitiated)
        case .video:
            video.record(failed: failed, clientInitiated: clientInitiated)
        case .muxed:
            muxed.record(failed: failed, clientInitiated: clientInitiated)
        case .unknown:
            unknown.record(failed: failed, clientInitiated: clientInitiated)
        }
    }

    private var buckets: [PlaybackHealthContentKeyMediaTelemetry] {
        [audio, video, muxed, unknown]
    }
}

struct PlaybackHealthRequestTimingAggregate: Equatable, Sendable {
    let requestCount: Int
    let durationSampleCount: Int
    let summedRequestDuration: Double?

    init(requestDurations: [Double?]) {
        requestCount = requestDurations.count
        let safeDurations = requestDurations.compactMap { duration -> Double? in
            guard let duration, duration.isFinite, duration >= 0 else { return nil }
            return duration
        }
        durationSampleCount = safeDurations.count
        summedRequestDuration = safeDurations.isEmpty ? nil : safeDurations.reduce(0, +)
    }
}

struct PlaybackHealthInitialRequestTelemetry: Equatable, Sendable {
    let playlists: PlaybackHealthRequestTimingAggregate
    let segments: PlaybackHealthRequestTimingAggregate
    let contentKeys: PlaybackHealthRequestTimingAggregate
}

struct PlaybackHealthLikelyToKeepUpSample: Equatable, Sendable {
    let occurredAt: Date
    let mediaTime: Double?
    let timeTaken: Double?
    let loadedRangeDuration: Double?
}

struct PlaybackHealthLikelyToKeepUpTelemetry: Equatable, Sendable {
    var eventCount = 0
    var initial: PlaybackHealthLikelyToKeepUpSample?
    var latest: PlaybackHealthLikelyToKeepUpSample?
    var initialRequests: PlaybackHealthInitialRequestTelemetry?

    mutating func record(
        occurredAt: Date,
        mediaTime: Double?,
        timeTaken: Double?,
        loadedRangeDuration: Double?,
        initialRequests: PlaybackHealthInitialRequestTelemetry?
    ) {
        let sample = PlaybackHealthLikelyToKeepUpSample(
            occurredAt: occurredAt,
            mediaTime: Self.nonnegative(mediaTime),
            timeTaken: Self.nonnegative(timeTaken),
            loadedRangeDuration: Self.nonnegative(loadedRangeDuration)
        )
        eventCount += 1
        latest = sample
        if let initialRequests, initial == nil {
            initial = sample
            self.initialRequests = initialRequests
        }
    }

    private static func nonnegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}

struct PlaybackHealthSeekTelemetry: Equatable, Sendable {
    var startedCount = 0
    var completedCount = 0
    var inBufferCount = 0
    var outsideBufferCount = 0
    var unknownBufferCount = 0
    var inProgressCount = 0
    var latestStartedAt: Date?
    var latestCompletedAt: Date?
    var latestDidSeekInBuffer: Bool?

    mutating func recordStarted(occurredAt: Date) {
        startedCount += 1
        inProgressCount += 1
        latestStartedAt = occurredAt
    }

    mutating func recordCompleted(
        didSeekInBuffer: Bool?,
        occurredAt: Date
    ) {
        completedCount += 1
        inProgressCount = max(inProgressCount - 1, 0)
        latestCompletedAt = occurredAt
        latestDidSeekInBuffer = didSeekInBuffer
        switch didSeekInBuffer {
        case true:
            inBufferCount += 1
        case false:
            outsideBufferCount += 1
        case nil:
            unknownBufferCount += 1
        }
    }
}

struct PlaybackHealthPlaybackSummaryTelemetry: Equatable, Sendable {
    let occurredAt: Date
    let error: PlaybackDiagnosticsError?
    let errorDidRecover: Bool?
    let recoverableErrorCount: Int?
    let stallCount: Int?
    let variantSwitchCount: Int?
    let playbackDuration: Int?
    let mediaResourceRequestCount: Int?
    let timeSpentRecoveringFromStall: Double?
    let timeSpentInInitialStartup: Double?
    let timeWeightedAverageBitrate: Int?
    let timeWeightedPeakBitrate: Int?

    init(
        occurredAt: Date,
        errorDomain: String?,
        errorCode: Int?,
        errorDidRecover: Bool?,
        recoverableErrorCount: Int,
        stallCount: Int,
        variantSwitchCount: Int,
        playbackDuration: Int,
        mediaResourceRequestCount: Int,
        timeSpentRecoveringFromStall: Double,
        timeSpentInInitialStartup: Double,
        timeWeightedAverageBitrate: Int,
        timeWeightedPeakBitrate: Int
    ) {
        self.occurredAt = occurredAt
        self.error = errorCode.map {
            PlaybackDiagnosticsError(
                occurredAt: occurredAt,
                domain: sanitizedPlaybackHealthErrorDomain(errorDomain),
                code: $0
            )
        }
        self.errorDidRecover = errorCode == nil ? nil : errorDidRecover
        self.recoverableErrorCount = Self.nonnegative(recoverableErrorCount)
        self.stallCount = Self.nonnegative(stallCount)
        self.variantSwitchCount = Self.nonnegative(variantSwitchCount)
        self.playbackDuration = Self.nonnegative(playbackDuration)
        self.mediaResourceRequestCount = Self.nonnegative(mediaResourceRequestCount)
        self.timeSpentRecoveringFromStall = Self.nonnegative(timeSpentRecoveringFromStall)
        self.timeSpentInInitialStartup = Self.nonnegative(timeSpentInInitialStartup)
        self.timeWeightedAverageBitrate = Self.nonnegative(timeWeightedAverageBitrate)
        self.timeWeightedPeakBitrate = Self.nonnegative(timeWeightedPeakBitrate)
    }

    private static func nonnegative(_ value: Int) -> Int? {
        value >= 0 ? value : nil
    }

    private static func nonnegative(_ value: Double) -> Double? {
        value.isFinite && value >= 0 ? value : nil
    }
}

struct PlaybackHealthTerminalFailure: Equatable, Sendable {
    let occurredAt: Date
    let mediaTime: Double?
    let error: PlaybackDiagnosticsError
}

struct PlaybackHealthNaturalEndEvidence: Equatable, Sendable {
    let occurredAt: Date
    let mediaTime: Double?
}

struct PlaybackHealthVariant: Equatable, Sendable {
    let peakBitRate: Double?
    let averageBitRate: Double?
    let resolution: String?
    let frameRate: Double?
}

struct PlaybackHealthVariantTransition: Equatable, Sendable {
    let occurredAt: Date
    let from: PlaybackHealthVariant?
    let to: PlaybackHealthVariant
    let succeeded: Bool
}

struct PlaybackHealthVariantSwitchTelemetry: Equatable, Sendable {
    static let recentTransitionCapacity = 20

    var totalCount = 0
    var succeededCount = 0
    var failedCount = 0
    var upCount = 0
    var downCount = 0
    var lateralCount = 0
    var unknownDirectionCount = 0
    var latestOccurredAt: Date?
    var latestSucceeded: Bool?
    var latestFrom: PlaybackHealthVariant?
    var latestTo: PlaybackHealthVariant?
    var recentTransitions: [PlaybackHealthVariantTransition] = []

    mutating func record(
        from: PlaybackHealthVariant?,
        to: PlaybackHealthVariant,
        succeeded: Bool,
        occurredAt: Date
    ) {
        totalCount += 1
        if succeeded {
            succeededCount += 1
        } else {
            failedCount += 1
        }

        if succeeded {
            let comparableBitRates: (from: Double, to: Double)?
            if let fromAverage = from?.averageBitRate,
               let toAverage = to.averageBitRate {
                comparableBitRates = (fromAverage, toAverage)
            } else if let fromPeak = from?.peakBitRate,
                      let toPeak = to.peakBitRate {
                comparableBitRates = (fromPeak, toPeak)
            } else {
                comparableBitRates = nil
            }

            if let comparableBitRates {
                if comparableBitRates.to > comparableBitRates.from {
                    upCount += 1
                } else if comparableBitRates.to < comparableBitRates.from {
                    downCount += 1
                } else {
                    lateralCount += 1
                }
            } else {
                unknownDirectionCount += 1
            }
        }

        latestOccurredAt = occurredAt
        latestSucceeded = succeeded
        latestFrom = from
        latestTo = to
        recentTransitions.append(
            PlaybackHealthVariantTransition(
                occurredAt: occurredAt,
                from: from,
                to: to,
                succeeded: succeeded
            )
        )
        if recentTransitions.count > Self.recentTransitionCapacity {
            recentTransitions.removeFirst(
                recentTransitions.count - Self.recentTransitionCapacity
            )
        }
    }
}

enum PlaybackHealthWaitKind: String, Equatable, Sendable {
    case initial
    case postStart
    case seek
}

struct PlaybackHealthWaitingTelemetry: Equatable, Sendable {
    var initialWaitCount = 0
    var postStartWaitCount = 0
    var seekWaitCount = 0
    var currentKind: PlaybackHealthWaitKind?
    var lastKind: PlaybackHealthWaitKind?
    var currentWaitDuration: Double?
    var totalWaitDuration: Double = 0
    var longestWaitDuration: Double = 0
    var lastWaitDuration: Double?
    var lastReason: String?
    var lastEndedAt: Date?
}

struct PlaybackHealthSlowDeliveryTelemetry: Equatable, Sendable {
    var audioCount = 0
    var videoCount = 0
    var muxedCount = 0
    var unknownCount = 0
    var worstAudioRatio: Double?
    var worstVideoRatio: Double?
    var worstMuxedRatio: Double?
    var worstUnknownRatio: Double?
    var latestOccurredAt: Date?
    var latestMediaType: PlaybackHealthMediaType?

    var totalCount: Int {
        audioCount + videoCount + muxedCount + unknownCount
    }

    var worstRatio: Double? {
        [
            worstAudioRatio,
            worstVideoRatio,
            worstMuxedRatio,
            worstUnknownRatio
        ]
        .compactMap { $0 }
        .max()
    }
}

struct PlaybackHealthMonitorTelemetry: Equatable, Sendable {
    var streamState: PlaybackHealthMonitorStreamState
    var streamFailure: PlaybackDiagnosticsError?
    var fallbackReason: PlaybackHealthFallbackReason?
    var playlistRequestCount: Int
    var segmentRequestCount: Int
    var healthyPlaylistRequestCount: Int
    var healthySegmentRequestCount: Int
    var failedPlaylistRequestCount: Int
    var failedSegmentRequestCount: Int
    var audioRequestCount: Int
    var videoRequestCount: Int
    var muxedRequestCount: Int
    var unknownRequestCount: Int
    var stallCount: Int
    var latestStallAt: Date?
    var classifier: PlaybackHealthClassifierTelemetry
    var latestFailureContext: PlaybackHealthRequestFailureContext?
    var terminalFailure: PlaybackHealthTerminalFailure?
    var naturalEnd: PlaybackHealthNaturalEndEvidence?
    var variantSwitches: PlaybackHealthVariantSwitchTelemetry
    var waiting: PlaybackHealthWaitingTelemetry
    var slowDelivery: PlaybackHealthSlowDeliveryTelemetry
    var contentKeys: PlaybackHealthContentKeyTelemetry
    var likelyToKeepUp: PlaybackHealthLikelyToKeepUpTelemetry
    var seeks: PlaybackHealthSeekTelemetry
    var playbackSummary: PlaybackHealthPlaybackSummaryTelemetry?
    var requestTrace: PlaybackHealthRequestTraceTelemetry

    static func initial(for streamState: PlaybackHealthMonitorStreamState) -> Self {
        Self(
            streamState: streamState,
            streamFailure: nil,
            fallbackReason: streamState == .fallbackObserving ? .legacyOS : nil,
            playlistRequestCount: 0,
            segmentRequestCount: 0,
            healthyPlaylistRequestCount: 0,
            healthySegmentRequestCount: 0,
            failedPlaylistRequestCount: 0,
            failedSegmentRequestCount: 0,
            audioRequestCount: 0,
            videoRequestCount: 0,
            muxedRequestCount: 0,
            unknownRequestCount: 0,
            stallCount: 0,
            latestStallAt: nil,
            classifier: .empty,
            latestFailureContext: nil,
            terminalFailure: nil,
            naturalEnd: nil,
            variantSwitches: PlaybackHealthVariantSwitchTelemetry(),
            waiting: PlaybackHealthWaitingTelemetry(),
            slowDelivery: PlaybackHealthSlowDeliveryTelemetry(),
            contentKeys: PlaybackHealthContentKeyTelemetry(),
            likelyToKeepUp: PlaybackHealthLikelyToKeepUpTelemetry(),
            seeks: PlaybackHealthSeekTelemetry(),
            playbackSummary: nil,
            requestTrace: PlaybackHealthRequestTraceTelemetry()
        )
    }

    var observedHLSRequestCount: Int {
        playlistRequestCount + segmentRequestCount + contentKeys.totalCount
    }

    var healthyDropCount: Int {
        healthyPlaylistRequestCount
            + healthySegmentRequestCount
            + contentKeys.succeededCount
    }
}

struct PlaybackDiagnosticsHistory: Equatable, Sendable {
    let receivedCount: Int
    let retainedCount: Int
    let droppedCount: Int
    let clearedCount: Int

    static let empty = Self(
        receivedCount: 0,
        retainedCount: 0,
        droppedCount: 0,
        clearedCount: 0
    )

    var isIncomplete: Bool {
        droppedCount > 0 || clearedCount > 0
    }
}

struct PlaybackDiagnosticsSnapshot: Equatable, Sendable {
    struct Session: Equatable, Sendable {
        let capturedAt: Date
        let startedAt: Date?
        let availability: PlaybackDiagnosticsAvailability
        let backend: String
        let monitorAttached: Bool
        let sessionID: UUID?
        let assetIdentifier: String?

        init(
            capturedAt: Date,
            startedAt: Date? = nil,
            availability: PlaybackDiagnosticsAvailability,
            backend: String,
            monitorAttached: Bool,
            sessionID: UUID?,
            assetIdentifier: String?
        ) {
            self.capturedAt = capturedAt
            self.startedAt = startedAt
            self.availability = availability
            self.backend = backend
            self.monitorAttached = monitorAttached
            self.sessionID = sessionID
            self.assetIdentifier = assetIdentifier
        }
    }

    struct Playback: Equatable, Sendable {
        let itemStatus: String
        let timeControlStatus: String
        let waitingReason: String?
        let rate: Double?
        let currentTime: Double?
        let duration: Double?
        let bufferedUntil: Double?
        let bufferHeadroom: Double?
        let loadedRangeCount: Int
        let seekableRangeCount: Int
        let isPlaybackLikelyToKeepUp: Bool
        let isPlaybackBufferEmpty: Bool
        let isPlaybackBufferFull: Bool
        let automaticallyWaitsToMinimizeStalling: Bool
        let isMuted: Bool
        let volume: Double
        let playbackType: String?
        let isLikelyHLS: Bool?
        let resolution: String?
        let frameRate: Double?
        let preferredForwardBufferDuration: Double
        let preferredPeakBitRate: Double
        let preferredMaximumResolution: String?
    }

    struct Network: Equatable, Sendable {
        let accessLogEventCount: Int
        let mediaRequestCount: Int?
        let numberOfStalls: Int?
        let droppedVideoFrameCount: Int?
        let overdueDownloadCount: Int?
        let bytesTransferred: Int64?
        let transferDuration: Double?
        let observedBitRate: Double?
        let indicatedBitRate: Double?
        let indicatedAverageBitRate: Double?
        let averageVideoBitRate: Double?
        let averageAudioBitRate: Double?
        let observedBitRateStandardDeviation: Double?
        let switchBitRate: Double?
        let segmentsDownloadedDuration: Double?
        let durationWatched: Double?
        let startupTime: Double?
        let serverAddressChangeCount: Int?

        static func aggregatingAccessLogPeriods(_ periods: [Self]) -> Self {
            guard let latest = periods.last else {
                return Self(
                    accessLogEventCount: 0,
                    mediaRequestCount: nil,
                    numberOfStalls: nil,
                    droppedVideoFrameCount: nil,
                    overdueDownloadCount: nil,
                    bytesTransferred: nil,
                    transferDuration: nil,
                    observedBitRate: nil,
                    indicatedBitRate: nil,
                    indicatedAverageBitRate: nil,
                    averageVideoBitRate: nil,
                    averageAudioBitRate: nil,
                    observedBitRateStandardDeviation: nil,
                    switchBitRate: nil,
                    segmentsDownloadedDuration: nil,
                    durationWatched: nil,
                    startupTime: nil,
                    serverAddressChangeCount: nil
                )
            }

            // ponytail: access-log periods are few and this O(n) scan runs only
            // while the dashboard is open; cache incrementally if that ceiling changes.
            return Self(
                accessLogEventCount: periods.count,
                mediaRequestCount: total(periods.map(\.mediaRequestCount)),
                numberOfStalls: total(periods.map(\.numberOfStalls)),
                droppedVideoFrameCount: total(periods.map(\.droppedVideoFrameCount)),
                overdueDownloadCount: total(periods.map(\.overdueDownloadCount)),
                bytesTransferred: total(periods.map(\.bytesTransferred)),
                transferDuration: total(periods.map(\.transferDuration)),
                observedBitRate: latest.observedBitRate,
                indicatedBitRate: latest.indicatedBitRate,
                indicatedAverageBitRate: latest.indicatedAverageBitRate,
                averageVideoBitRate: latest.averageVideoBitRate,
                averageAudioBitRate: latest.averageAudioBitRate,
                observedBitRateStandardDeviation: latest.observedBitRateStandardDeviation,
                switchBitRate: latest.switchBitRate,
                segmentsDownloadedDuration: total(periods.map(\.segmentsDownloadedDuration)),
                durationWatched: total(periods.map(\.durationWatched)),
                startupTime: latest.startupTime,
                serverAddressChangeCount: total(periods.map(\.serverAddressChangeCount))
            )
        }

        private static func total(_ values: [Int?]) -> Int? {
            guard values.allSatisfy({ $0 != nil }) else { return nil }
            return values.compactMap { $0 }.reduce(0, +)
        }

        private static func total(_ values: [Int64?]) -> Int64? {
            guard values.allSatisfy({ $0 != nil }) else { return nil }
            return values.compactMap { $0 }.reduce(0, +)
        }

        private static func total(_ values: [Double?]) -> Double? {
            guard values.allSatisfy({ $0 != nil }) else { return nil }
            return values.compactMap { $0 }.reduce(0, +)
        }
    }

    let session: Session
    let playback: Playback
    let network: Network
    let audioTracks: [PlaybackDiagnosticsTrack]
    let subtitleTracks: [PlaybackDiagnosticsTrack]
    let errorLogEventCount: Int
    let recentErrors: [PlaybackDiagnosticsError]
    let recentHealthEvents: [PlaybackHealthEvent]
    let monitor: PlaybackHealthMonitorTelemetry?
    let history: PlaybackDiagnosticsHistory
    let storyboard: PlaybackDiagnosticsStoryboard

    static func unavailable(_ availability: PlaybackDiagnosticsAvailability) -> Self {
        return Self(
            session: Session(
                capturedAt: Date(),
                availability: availability,
                backend: availability == .unsupportedBackend ? "Non-AVPlayer" : "AVPlayer",
                monitorAttached: false,
                sessionID: nil,
                assetIdentifier: nil
            ),
            playback: Playback(
                itemStatus: "unavailable",
                timeControlStatus: "unavailable",
                waitingReason: nil,
                rate: nil,
                currentTime: nil,
                duration: nil,
                bufferedUntil: nil,
                bufferHeadroom: nil,
                loadedRangeCount: 0,
                seekableRangeCount: 0,
                isPlaybackLikelyToKeepUp: false,
                isPlaybackBufferEmpty: false,
                isPlaybackBufferFull: false,
                automaticallyWaitsToMinimizeStalling: false,
                isMuted: false,
                volume: 1,
                playbackType: nil,
                isLikelyHLS: nil,
                resolution: nil,
                frameRate: nil,
                preferredForwardBufferDuration: 0,
                preferredPeakBitRate: 0,
                preferredMaximumResolution: nil
            ),
            network: Network(
                accessLogEventCount: 0,
                mediaRequestCount: nil,
                numberOfStalls: nil,
                droppedVideoFrameCount: nil,
                overdueDownloadCount: nil,
                bytesTransferred: nil,
                transferDuration: nil,
                observedBitRate: nil,
                indicatedBitRate: nil,
                indicatedAverageBitRate: nil,
                averageVideoBitRate: nil,
                averageAudioBitRate: nil,
                observedBitRateStandardDeviation: nil,
                switchBitRate: nil,
                segmentsDownloadedDuration: nil,
                durationWatched: nil,
                startupTime: nil,
                serverAddressChangeCount: nil
            ),
            audioTracks: [],
            subtitleTracks: [],
            errorLogEventCount: 0,
            recentErrors: [],
            recentHealthEvents: [],
            monitor: nil,
            history: .empty,
            storyboard: .empty
        )
    }

    func issues() -> [PlaybackDiagnosticsIssue] {
        var result: [PlaybackDiagnosticsIssue] = []
        let hasNaturalEndEvidence = monitor?.naturalEnd != nil
        let isFinalVODRangeBuffered = playback.playbackType == "VOD"
            && playback.currentTime.map { currentTime in
                guard let duration = playback.duration,
                      let bufferedUntil = playback.bufferedUntil,
                      currentTime.isFinite,
                      currentTime >= 0,
                      duration.isFinite,
                      duration > 0,
                      bufferedUntil.isFinite,
                      bufferedUntil >= 0 else {
                    return false
                }
                return currentTime >= max(duration - 3, 0)
                    && bufferedUntil >= max(duration - 0.25, 0)
            } == true
        let hasRecentStallEvidence = monitor?.latestStallAt.map {
            abs(session.capturedAt.timeIntervalSince($0)) <= 10
        } == true
        let hasIndependentDeliveryPressure = playback.isPlaybackBufferEmpty
            || !playback.isPlaybackLikelyToKeepUp
            || hasRecentStallEvidence
        let isCurrentDeliveryPressureWarning = playback.itemStatus == "ready"
            && playback.timeControlStatus == "waiting"
            && monitor?.waiting.currentKind == .postStart
            && (monitor?.waiting.currentWaitDuration ?? 0) >= 1
            && hasIndependentDeliveryPressure

        switch session.availability {
        case .activeAVMetrics:
            break
        case .startingAVMetrics:
            result.append(
                issue(
                    "metrics-starting",
                    .observation,
                    .coverage,
                    "Starting HLS observation",
                    "AVMetrics is attaching to the current player item.",
                    "Keep playback running while the observer starts."
                )
            )
        case .failedAVMetrics:
            result.append(
                issue(
                    "metrics-failed",
                    .warning,
                    .coverage,
                    "HLS metric observation failed",
                    monitor?.streamFailure.map {
                        "Sanitized stream failure: \($0.domain ?? "unlisted") / \($0.code)."
                    } ?? "The AVMetrics stream failed without a listed error domain.",
                    "Use the sanitized error-log fallback and include this state in a diagnostic export."
                )
            )
        case .endedAVMetrics:
            if !hasNaturalEndEvidence {
                result.append(
                    issue(
                        "metrics-ended",
                        .notice,
                        .coverage,
                        "HLS metric observation ended",
                        "The AVMetrics stream ended while the player item remains attached.",
                        "Continue with fallback evidence and include the observer state in a diagnostic export."
                    )
                )
            }
        case .activeErrorLogFallback:
            if monitor?.fallbackReason != .metricsEnded || !hasNaturalEndEvidence {
                let detail: String
                switch monitor?.fallbackReason {
                case .metricsFailed:
                    detail = "AVMetrics failed; sanitized error-log and stall observation remain active with reduced attribution."
                case .metricsEnded:
                    detail = "AVMetrics ended; sanitized error-log and stall observation remain active with reduced attribution."
                default:
                    detail = "This macOS version provides error-log and stall evidence without reliable HLS media attribution."
                }
                result.append(
                    issue(
                        "reduced-attribution",
                        .notice,
                        .coverage,
                        "Reduced HLS attribution",
                        detail,
                        "Use macOS 15 or newer for typed HLS request metrics."
                    )
                )
            }
        case .monitoringDisabled:
            result.append(
                issue(
                    "monitoring-disabled",
                    .warning,
                    .coverage,
                    "Health monitoring is disabled",
                    "Enable PlayerManager playback-health monitoring before loading the item.",
                    "Reload the item after enabling monitoring."
                )
            )
        case .monitorNotAttached:
            result.append(
                issue(
                    "monitor-not-attached",
                    .warning,
                    .coverage,
                    "Health monitor is not attached",
                    "The current item was loaded outside PlayerKit's health-aware AVPlayer path.",
                    "Reload through PlayerManager's AVPlayer item-aware path."
                )
            )
        case .noPlayerItem:
            result.append(
                issue(
                    "no-item",
                    .notice,
                    .coverage,
                    "No active item",
                    "Start PlayerKit AVPlayer playback to collect diagnostics.",
                    nil
                )
            )
        case .unsupportedBackend:
            result.append(
                issue(
                    "unsupported-backend",
                    .warning,
                    .coverage,
                    "Unsupported playback backend",
                    "Advanced HLS diagnostics are available only for PlayerKit's AVPlayer backend.",
                    "Use the AVPlayer backend for this experiment."
                )
            )
        }

        if (session.availability == .activeAVMetrics
                || session.availability == .activeErrorLogFallback),
           playback.isLikelyHLS != true {
            result.append(
                issue(
                    "waiting-hls-evidence",
                    .observation,
                    .coverage,
                    "Waiting for HLS evidence",
                    "The monitor is attached, but neither the source path nor typed HLS metrics has confirmed HLS yet.",
                    "Continue playback until HLS request metrics arrive."
                )
            )
        }

        if let terminalFailure = monitor?.terminalFailure {
            result.append(
                issue(
                    "terminal-playback-failure",
                    .critical,
                    .active,
                    "Playback failed before the end",
                    "AVFoundation reported \(terminalFailure.error.domain ?? "an unlisted domain") / \(terminalFailure.error.code) at \(Self.decimal(terminalFailure.mediaTime)) seconds.",
                    "Copy the sanitized diagnostic report and try another title to separate item-specific from device-wide failure."
                )
            )
        }

        if playback.itemStatus == "failed", monitor?.terminalFailure == nil {
            result.append(
                issue(
                    "item-failed",
                    .critical,
                    .active,
                    "Player item failed",
                    "AVFoundation marked the active item as failed.",
                    "Copy the sanitized diagnostic report for investigation."
                )
            )
        }

        if playback.timeControlStatus == "waiting" {
            let detail: String
            if monitor?.waiting.currentKind == .seek {
                detail =
                    "\(Self.decimal(monitor?.waiting.currentWaitDuration)) seconds in a seek-related " +
                    "wait. \(playback.waitingReason ?? "AVPlayer reported no waiting reason.")"
            } else if isCurrentDeliveryPressureWarning {
                detail =
                    "\(Self.decimal(monitor?.waiting.currentWaitDuration)) seconds in the current " +
                    "post-start wait with independent buffer, keep-up, or recent stall evidence. " +
                    "\(playback.waitingReason ?? "AVPlayer reported no waiting reason.")"
            } else {
                detail =
                    playback.waitingReason
                    ?? "AVPlayer is in an observational wait without a reported reason."
            }
            result.append(
                issue(
                    "waiting",
                    isCurrentDeliveryPressureWarning ? .warning : .observation,
                    .active,
                    isCurrentDeliveryPressureWarning
                        ? "Delivery pressure during playback wait"
                        : monitor?.waiting.currentKind == .seek
                            ? "Playback is waiting during a seek"
                            : "Playback wait observed",
                    detail,
                    isCurrentDeliveryPressureWarning
                        ? "Correlate the wait with buffer and delivery evidence."
                        : "Treat the wait as timing context unless independent delivery evidence appears."
                )
            )
        }

        let isReadyAndActive = playback.itemStatus == "ready"
            && (playback.timeControlStatus == "playing" || isCurrentDeliveryPressureWarning)

        if isReadyAndActive, playback.isPlaybackBufferEmpty {
            result.append(
                issue(
                    "buffer-empty",
                    .warning,
                    .active,
                    "Playback buffer is empty",
                    "Playback may rebuffer until more media arrives.",
                    "Compare audio/video delivery and recent request failures."
                )
            )
        } else if playback.timeControlStatus == "playing",
                  !isFinalVODRangeBuffered,
                  let headroom = playback.bufferHeadroom,
                  headroom < 3 {
            result.append(
                issue(
                    "low-buffer",
                    .warning,
                    .active,
                    "Low buffer headroom",
                    String(format: "%.1f seconds remain ahead of the playhead.", headroom),
                    "Watch whether throughput recovers before the buffer empties."
                )
            )
        }

        if playback.timeControlStatus == "playing",
           !playback.isPlaybackLikelyToKeepUp {
            result.append(
                issue(
                    "not-likely-to-keep-up",
                    .warning,
                    .active,
                    "Playback may not keep up",
                    "AVFoundation does not currently expect uninterrupted playback.",
                    "Compare buffer headroom with observed and indicated bitrate."
                )
            )
        }

        if playback.timeControlStatus == "playing",
           let observed = network.observedBitRate,
           let indicated = network.indicatedBitRate,
           indicated > 0,
           observed < indicated * 0.7 {
            let ratio = observed / indicated
            result.append(
                issue(
                    "throughput-shortfall",
                    .warning,
                    .active,
                    "Network throughput is below rendition demand",
                    String(format: "Observed throughput is %.0f%% of the indicated bitrate.", ratio * 100),
                    "Treat this as delivery pressure, not proof of corrupt media."
                )
            )
        }

        if let overdue = network.overdueDownloadCount, overdue > 0 {
            result.append(
                issue(
                    "overdue-downloads",
                    .notice,
                    .historical,
                    "Slow segment downloads observed",
                    "\(overdue) download\(overdue == 1 ? "" : "s") exceeded the expected delivery time.",
                    "Compare their timing with waits or stalls."
                )
            )
        }

        if let stalls = network.numberOfStalls, stalls > 0 {
            result.append(
                issue(
                    "access-log-stalls",
                    .notice,
                    .historical,
                    "Playback stalls recorded",
                    "The current playback session reports \(stalls) stall\(stalls == 1 ? "" : "s").",
                    "Check whether stalls align with request failures or buffer pressure."
                )
            )
        }

        if let dropped = network.droppedVideoFrameCount, dropped > 0 {
            result.append(
                issue(
                    "dropped-frames",
                    .notice,
                    .historical,
                    "Dropped video frames",
                    "\(dropped) video frame\(dropped == 1 ? "" : "s") were dropped.",
                    "Compare with rendition bitrate and device load."
                )
            )
        }

        if let monitor, monitor.variantSwitches.failedCount > 0 {
            result.append(
                issue(
                    "variant-switch-failures",
                    .notice,
                    .historical,
                    "Rendition switches failed",
                    "\(monitor.variantSwitches.failedCount) of \(monitor.variantSwitches.totalCount) observed switch completions failed.",
                    "Treat adaptive switching as delivery context; it does not prove corrupt content."
                )
            )
        }

        if let monitor, monitor.slowDelivery.totalCount > 0 {
            result.append(
                issue(
                    "slow-segment-delivery",
                    .notice,
                    .historical,
                    "Segment requests exceeded their media duration",
                    "\(monitor.slowDelivery.totalCount) typed segment request(s), including any failed requests, took longer than their segment duration; worst observed ratio was \(Self.decimal(monitor.slowDelivery.worstRatio))×.",
                    "Correlate with waits, stalls, and selected audio before treating it as user-visible impact."
                )
            )
        }

        if let contentKeys = monitor?.contentKeys, contentKeys.failedCount > 0 {
            result.append(
                issue(
                    "content-key-request-failures",
                    .notice,
                    .historical,
                    "Content-key request failures observed",
                    "\(contentKeys.failedCount) of \(contentKeys.totalCount) typed content-key request(s) carried error evidence; \(contentKeys.succeededCount) completed without it.",
                    "Correlate key delivery with startup time and playback errors; no key identifier or URL is retained."
                )
            )
        }

        if let requestTrace = monitor?.requestTrace {
            let suspiciousResponseCount = requestTrace.entries.filter { entry in
                guard entry.kind == .playlist || entry.kind == .segment else {
                    return false
                }
                return entry.mimeCategory == .html || entry.mimeCategory == .json
            }.count

            if suspiciousResponseCount > 0 {
                result.append(
                    issue(
                        "unexpected-hls-response-type",
                        .notice,
                        .historical,
                        "Unexpected HLS response type observed",
                        "\(suspiciousResponseCount) retained playlist or segment request(s) reported HTML or JSON instead of a recognized HLS media type.",
                        "Check origin, CDN, authentication, and entitlement responses for an error document returned to a media request."
                    )
                )
            }
        }

        if let waiting = monitor?.waiting, waiting.postStartWaitCount > 0 {
            result.append(
                issue(
                    "post-start-wait-history",
                    .notice,
                    .historical,
                    "Post-start waits observed",
                    "\(waiting.postStartWaitCount) post-start wait(s) were observed; waits alone do not prove rebuffering. All wait kinds total \(Self.decimal(waiting.totalWaitDuration)) seconds with \(Self.decimal(waiting.longestWaitDuration)) seconds longest.",
                    "Correlate these waits with buffer, keep-up, stall, and request evidence."
                )
            )
        }

        if playback.itemStatus == "ready", playback.isMuted {
            result.append(
                issue(
                    "player-muted",
                    .warning,
                    .active,
                    "Player audio is muted",
                    "The current AVPlayer is muted; this is local player state, not evidence of a content defect.",
                    "Unmute the player before investigating the stream."
                )
            )
        } else if playback.itemStatus == "ready", playback.volume <= 0.001 {
            result.append(
                issue(
                    "player-volume-zero",
                    .warning,
                    .active,
                    "Player volume is zero",
                    "The current AVPlayer volume is zero; this is local player state, not evidence of a content defect.",
                    "Raise player volume before investigating the stream."
                )
            )
        }

        if playback.itemStatus == "ready",
           playback.timeControlStatus == "playing",
           !audioTracks.isEmpty,
           !audioTracks.contains(where: \.isSelected) {
            result.append(
                issue(
                    "missing-audio-selection",
                    .warning,
                    .active,
                    "No audio track is selected",
                    "The item exposes audio tracks but AVFoundation has no active selection.",
                    "Select an audio track and capture another incident if audio remains missing."
                )
            )
        }

        if let error = recentErrors.max(by: Self.errorRecencySort) {
            let diagnosis = [error.domain, String(error.code)]
                .compactMap { $0 }
                .joined(separator: " / ")
            result.append(
                issue(
                    "error-log",
                    .notice,
                    .historical,
                    "AVFoundation error log is not empty",
                    diagnosis.isEmpty ? "A sanitized error entry was recorded." : diagnosis,
                    "Use the domain/code in the copied report; no raw error text is retained."
                )
            )
        }

        if let strongest = recentHealthEvents.max(by: { $0.confidence.rank < $1.confidence.rank }) {
            let candidateCount = max(history.receivedCount, recentHealthEvents.count)
            let level: PlaybackDiagnosticsLevel
            switch strongest.confidence {
            case .low:
                level = .notice
            case .medium:
                level = .notice
            case .high:
                level = .warning
            }
            result.append(
                issue(
                    "health-signals",
                    level,
                    .historical,
                    "\(candidateCount) unvalidated delivery candidate\(candidateCount == 1 ? "" : "s")",
                    "Raw calibration evidence only. Strongest retained signal: \(strongest.signalKind.rawValue), \(strongest.mediaType.rawValue), \(strongest.confidence.rawValue) candidate confidence.",
                    "Correlate the candidate with a user-observed incident before classifying content."
                )
            )
        }

        if monitor?.classifier.sampleCapReached == true {
            result.append(
                issue(
                    "sample-cap",
                    .notice,
                    .coverage,
                    "Calibration sample cap reached",
                    "Additional candidates are counted as suppressed after \(monitor?.classifier.sampleCap ?? 0) emitted samples.",
                    "Use aggregate counters after the retained sample cap."
                )
            )
        }

        if history.isIncomplete {
            result.append(
                issue(
                    "history-incomplete",
                    .notice,
                    .coverage,
                    "Recent signal history is partial",
                    "\(history.droppedCount) signal(s) were dropped by retention and \(history.clearedCount) were cleared manually.",
                    "Use aggregate counters to interpret the retained sample."
                )
            )
        }

        return result.sorted { lhs, rhs in
            if lhs.level == rhs.level {
                return lhs.title < rhs.title
            }
            return lhs.level > rhs.level
        }
    }

    func report() -> String {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let hasItem = playback.itemStatus != "unavailable"
        let hasSessionEvidence = hasItem
            || session.startedAt != nil
            || storyboard.sessionStartedAt != nil
            || session.sessionID != nil
        let selectedAudioTrack = audioTracks
            .sorted(by: Self.trackSort)
            .first(where: \.isSelected)
        let metricsCoverage: String
        switch session.availability {
        case .activeAVMetrics:
            metricsCoverage = "typed_avmetrics"
        case .startingAVMetrics:
            metricsCoverage = "typed_avmetrics_starting"
        case .activeErrorLogFallback, .failedAVMetrics, .endedAVMetrics:
            metricsCoverage = "reduced_error_log_fallback"
        case .monitoringDisabled, .monitorNotAttached:
            metricsCoverage = "not_collected"
        case .noPlayerItem, .unsupportedBackend:
            metricsCoverage = "unavailable"
        }
        var lines = [
            "PlayerKit HLS Diagnostics",
            "schema_version=2",
            "value_semantics=measured values are direct platform observations; inferred values are labeled incidents; unknown means unavailable or not measured",
            "privacy_scope=sanitized identifiers, counters, categories, and timings only; no URLs, request bodies, headers, comments, or display names",
            "number_format=en_US_POSIX fixed three-decimal seconds and bitrates",
            "timestamp_format=UTC ISO-8601 with milliseconds",
            "coverage_typed_hls_metrics=\(metricsCoverage)",
            "collection_limit_request_trace=\(PlaybackHealthRequestTraceTelemetry.capacity)",
            "collection_limit_variant_transitions=\(PlaybackHealthVariantSwitchTelemetry.recentTransitionCapacity)",
            "collection_limit_storyboard_samples=\(PlaybackDiagnosticsSessionReducer.sampleCapacity)",
            "collection_limit_storyboard_evidence=\(PlaybackDiagnosticsSessionReducer.evidenceCapacity)",
            "collection_limit_storyboard_incidents=\(PlaybackDiagnosticsSessionReducer.incidentCapacity)",
            "collection_limit_storyboard_bookmarks=\(PlaybackDiagnosticsSessionReducer.bookmarkCapacity)",
            "calibration_note=request and incident heuristics require correlated retained evidence; absence of retained evidence does not prove absence",
            "[measured]",
            "captured_at=\(Self.iso8601(session.capturedAt))",
            "os_version=\(Self.singleLine(ProcessInfo.processInfo.operatingSystemVersionString))",
            "app_version=\(Self.singleLine(appVersion ?? "unknown"))",
            "app_build=\(Self.singleLine(appBuild ?? "unknown"))",
            "availability=\(session.availability.rawValue)",
            "backend=\(Self.singleLine(session.backend))",
            "monitor_attached=\(session.monitorAttached)",
            "health_session_id=\(session.sessionID?.uuidString ?? "unknown")",
            "asset_id=\(Self.singleLine(session.assetIdentifier ?? "unknown"))",
            "session_started_at=\(Self.optionalISO8601(session.startedAt ?? storyboard.sessionStartedAt))",
            "session_ended_at=\(Self.optionalISO8601(storyboard.endedAt))",
            "first_playing_at=\(Self.optionalISO8601(storyboard.firstPlayingAt))",
            "first_likely_to_keep_up_at=\(Self.optionalISO8601(storyboard.firstLikelyToKeepUpAt))",
            "startup_to_playing_seconds=\(Self.interval(from: storyboard.sessionStartedAt ?? session.startedAt, to: storyboard.firstPlayingAt))",
            "startup_to_likely_to_keep_up_seconds=\(Self.interval(from: storyboard.sessionStartedAt ?? session.startedAt, to: storyboard.firstLikelyToKeepUpAt))",
            "session_elapsed_seconds=\(Self.interval(from: storyboard.sessionStartedAt ?? session.startedAt, to: storyboard.endedAt ?? session.capturedAt))",
            "item_status=\(Self.singleLine(playback.itemStatus))",
            "time_control=\(Self.singleLine(playback.timeControlStatus))",
            "waiting_reason=\(hasItem ? Self.singleLine(playback.waitingReason ?? "none") : "unknown")",
            "rate=\(hasItem ? Self.decimal(playback.rate) : "unknown")",
            "current_seconds=\(hasItem ? Self.decimal(playback.currentTime) : "unknown")",
            "duration_seconds=\(hasItem ? Self.decimal(playback.duration) : "unknown")",
            "buffered_until_seconds=\(hasItem ? Self.decimal(playback.bufferedUntil) : "unknown")",
            "buffer_headroom_seconds=\(hasItem ? Self.decimal(playback.bufferHeadroom) : "unknown")",
            "loaded_range_count=\(Self.available(playback.loadedRangeCount, when: hasItem))",
            "seekable_range_count=\(Self.available(playback.seekableRangeCount, when: hasItem))",
            "likely_to_keep_up=\(Self.available(playback.isPlaybackLikelyToKeepUp, when: hasItem))",
            "buffer_empty=\(Self.available(playback.isPlaybackBufferEmpty, when: hasItem))",
            "buffer_full=\(Self.available(playback.isPlaybackBufferFull, when: hasItem))",
            "automatically_waits_to_minimize_stalling=\(Self.available(playback.automaticallyWaitsToMinimizeStalling, when: hasItem))",
            "muted=\(Self.available(playback.isMuted, when: hasItem))",
            "volume=\(hasItem ? Self.decimal(playback.volume) : "unknown")",
            "playback_type=\(hasItem ? Self.singleLine(playback.playbackType ?? "unknown") : "unknown")",
            "likely_hls=\(hasItem ? playback.isLikelyHLS.map(String.init) ?? "unknown" : "unknown")",
            "resolution=\(hasItem ? Self.singleLine(playback.resolution ?? "unknown") : "unknown")",
            "frame_rate=\(hasItem ? Self.decimal(playback.frameRate) : "unknown")",
            "preferred_forward_buffer_seconds=\(hasItem ? Self.decimal(playback.preferredForwardBufferDuration) : "unknown")",
            "preferred_peak_bitrate_bps=\(hasItem ? Self.decimal(playback.preferredPeakBitRate) : "unknown")",
            "preferred_maximum_resolution=\(hasItem ? Self.singleLine(playback.preferredMaximumResolution ?? "automatic") : "unknown")",
            "access_log_periods=\(Self.available(network.accessLogEventCount, when: hasItem))",
            "observed_bitrate_bps=\(hasItem ? Self.decimal(network.observedBitRate) : "unknown")",
            "indicated_bitrate_bps=\(hasItem ? Self.decimal(network.indicatedBitRate) : "unknown")",
            "indicated_average_bitrate_bps=\(hasItem ? Self.decimal(network.indicatedAverageBitRate) : "unknown")",
            "average_video_bitrate_bps=\(hasItem ? Self.decimal(network.averageVideoBitRate) : "unknown")",
            "average_audio_bitrate_bps=\(hasItem ? Self.decimal(network.averageAudioBitRate) : "unknown")",
            "observed_bitrate_standard_deviation_bps=\(hasItem ? Self.decimal(network.observedBitRateStandardDeviation) : "unknown")",
            "switch_bitrate_bps=\(hasItem ? Self.decimal(network.switchBitRate) : "unknown")",
            "media_requests=\(hasItem ? Self.integer(network.mediaRequestCount) : "unknown")",
            "stalls=\(hasItem ? Self.integer(network.numberOfStalls) : "unknown")",
            "dropped_video_frames=\(hasItem ? Self.integer(network.droppedVideoFrameCount) : "unknown")",
            "overdue_downloads=\(hasItem ? Self.integer(network.overdueDownloadCount) : "unknown")",
            "bytes_transferred=\(hasItem ? network.bytesTransferred.map(String.init) ?? "unknown" : "unknown")",
            "transfer_seconds=\(hasItem ? Self.decimal(network.transferDuration) : "unknown")",
            "segments_downloaded_seconds=\(hasItem ? Self.decimal(network.segmentsDownloadedDuration) : "unknown")",
            "duration_watched_seconds=\(hasItem ? Self.decimal(network.durationWatched) : "unknown")",
            "startup_seconds=\(hasItem ? Self.decimal(network.startupTime) : "unknown")",
            "server_address_change_count=\(hasItem ? Self.integer(network.serverAddressChangeCount) : "unknown")",
            "error_log_entries=\(Self.available(errorLogEventCount, when: hasItem))",
            "health_events_received=\(Self.available(history.receivedCount, when: hasSessionEvidence))",
            "health_events_retained=\(Self.available(history.retainedCount, when: hasSessionEvidence))",
            "health_events_dropped=\(Self.available(history.droppedCount, when: hasSessionEvidence))",
            "health_events_cleared=\(Self.available(history.clearedCount, when: hasSessionEvidence))",
            "storyboard_samples=\(Self.available(storyboard.samples.count, when: hasSessionEvidence))",
            "storyboard_evidence=\(Self.available(storyboard.evidence.count, when: hasSessionEvidence))",
            "automatic_incidents=\(Self.available(storyboard.incidents.count, when: hasSessionEvidence))",
            "bookmarks=\(Self.available(storyboard.bookmarks.count, when: hasSessionEvidence))",
            "selected_audio_track_id=\(Self.singleLine(selectedAudioTrack?.identifier ?? "unknown"))",
            "selected_audio_track_language=\(Self.singleLine(selectedAudioTrack?.languageCode ?? "unknown"))"
        ]

        if let monitor {
            lines.append(contentsOf: [
                "monitor_stream_state=\(monitor.streamState.rawValue)",
                "monitor_fallback_reason=\(monitor.fallbackReason?.rawValue ?? "none")",
                "monitor_stream_failure_domain=\(Self.singleLine(monitor.streamFailure?.domain ?? "none"))",
                "monitor_stream_failure_code=\(monitor.streamFailure.map { String($0.code) } ?? "none")",
                "natural_end_observed=\(monitor.naturalEnd != nil)",
                "natural_end_at=\(Self.optionalISO8601(monitor.naturalEnd?.occurredAt))",
                "natural_end_media_seconds=\(Self.decimal(monitor.naturalEnd?.mediaTime))",
                "hls_playlist_requests=\(monitor.playlistRequestCount)",
                "hls_segment_requests=\(monitor.segmentRequestCount)",
                "hls_requests_without_error_evidence=\(monitor.healthyDropCount)",
                "hls_failed_playlist_requests=\(monitor.failedPlaylistRequestCount)",
                "hls_failed_segment_requests=\(monitor.failedSegmentRequestCount)",
                "hls_audio_requests=\(monitor.audioRequestCount)",
                "hls_video_requests=\(monitor.videoRequestCount)",
                "hls_muxed_requests=\(monitor.muxedRequestCount)",
                "hls_unknown_requests=\(monitor.unknownRequestCount)",
                "metric_stalls=\(monitor.stallCount)",
                "metric_latest_stall_at=\(Self.optionalISO8601(monitor.latestStallAt))",
                "content_key_requests=\(monitor.contentKeys.totalCount)",
                "content_key_requests_succeeded=\(monitor.contentKeys.succeededCount)",
                "content_key_requests_failed=\(monitor.contentKeys.failedCount)",
                "content_key_requests_client_initiated=\(monitor.contentKeys.clientInitiatedCount)",
                "content_key_audio_total=\(monitor.contentKeys.audio.totalCount)",
                "content_key_audio_succeeded=\(monitor.contentKeys.audio.succeededCount)",
                "content_key_audio_failed=\(monitor.contentKeys.audio.failedCount)",
                "content_key_audio_client_initiated=\(monitor.contentKeys.audio.clientInitiatedCount)",
                "content_key_video_total=\(monitor.contentKeys.video.totalCount)",
                "content_key_video_succeeded=\(monitor.contentKeys.video.succeededCount)",
                "content_key_video_failed=\(monitor.contentKeys.video.failedCount)",
                "content_key_video_client_initiated=\(monitor.contentKeys.video.clientInitiatedCount)",
                "content_key_muxed_total=\(monitor.contentKeys.muxed.totalCount)",
                "content_key_muxed_succeeded=\(monitor.contentKeys.muxed.succeededCount)",
                "content_key_muxed_failed=\(monitor.contentKeys.muxed.failedCount)",
                "content_key_muxed_client_initiated=\(monitor.contentKeys.muxed.clientInitiatedCount)",
                "content_key_unknown_total=\(monitor.contentKeys.unknown.totalCount)",
                "content_key_unknown_succeeded=\(monitor.contentKeys.unknown.succeededCount)",
                "content_key_unknown_failed=\(monitor.contentKeys.unknown.failedCount)",
                "content_key_unknown_client_initiated=\(monitor.contentKeys.unknown.clientInitiatedCount)",
                "likely_to_keep_up_events=\(monitor.likelyToKeepUp.eventCount)",
                "likely_to_keep_up_initial_at=\(Self.optionalISO8601(monitor.likelyToKeepUp.initial?.occurredAt))",
                "likely_to_keep_up_initial_media_seconds=\(Self.decimal(monitor.likelyToKeepUp.initial?.mediaTime))",
                "likely_to_keep_up_initial_time_taken_seconds=\(Self.decimal(monitor.likelyToKeepUp.initial?.timeTaken))",
                "likely_to_keep_up_initial_loaded_seconds=\(Self.decimal(monitor.likelyToKeepUp.initial?.loadedRangeDuration))",
                "likely_to_keep_up_latest_at=\(Self.optionalISO8601(monitor.likelyToKeepUp.latest?.occurredAt))",
                "likely_to_keep_up_latest_media_seconds=\(Self.decimal(monitor.likelyToKeepUp.latest?.mediaTime))",
                "likely_to_keep_up_latest_time_taken_seconds=\(Self.decimal(monitor.likelyToKeepUp.latest?.timeTaken))",
                "likely_to_keep_up_latest_loaded_seconds=\(Self.decimal(monitor.likelyToKeepUp.latest?.loadedRangeDuration))",
                "initial_playlist_request_count=\(Self.integer(monitor.likelyToKeepUp.initialRequests?.playlists.requestCount))",
                "initial_playlist_duration_sample_count=\(Self.integer(monitor.likelyToKeepUp.initialRequests?.playlists.durationSampleCount))",
                "initial_playlist_request_seconds=\(Self.decimal(monitor.likelyToKeepUp.initialRequests?.playlists.summedRequestDuration))",
                "initial_segment_request_count=\(Self.integer(monitor.likelyToKeepUp.initialRequests?.segments.requestCount))",
                "initial_segment_duration_sample_count=\(Self.integer(monitor.likelyToKeepUp.initialRequests?.segments.durationSampleCount))",
                "initial_segment_request_seconds=\(Self.decimal(monitor.likelyToKeepUp.initialRequests?.segments.summedRequestDuration))",
                "initial_content_key_request_count=\(Self.integer(monitor.likelyToKeepUp.initialRequests?.contentKeys.requestCount))",
                "initial_content_key_duration_sample_count=\(Self.integer(monitor.likelyToKeepUp.initialRequests?.contentKeys.durationSampleCount))",
                "initial_content_key_request_seconds=\(Self.decimal(monitor.likelyToKeepUp.initialRequests?.contentKeys.summedRequestDuration))",
                "seek_started_count=\(monitor.seeks.startedCount)",
                "seek_completed_count=\(monitor.seeks.completedCount)",
                "seek_in_buffer_count=\(monitor.seeks.inBufferCount)",
                "seek_outside_buffer_count=\(monitor.seeks.outsideBufferCount)",
                "seek_unknown_buffer_count=\(monitor.seeks.unknownBufferCount)",
                "seek_in_progress_count=\(monitor.seeks.inProgressCount)",
                "seek_latest_started_at=\(Self.optionalISO8601(monitor.seeks.latestStartedAt))",
                "seek_latest_completed_at=\(Self.optionalISO8601(monitor.seeks.latestCompletedAt))",
                "seek_latest_in_buffer=\(monitor.seeks.latestDidSeekInBuffer.map(String.init) ?? "unknown")",
                "variant_switch_total=\(monitor.variantSwitches.totalCount)",
                "variant_switch_succeeded=\(monitor.variantSwitches.succeededCount)",
                "variant_switch_failed=\(monitor.variantSwitches.failedCount)",
                "variant_switch_up=\(monitor.variantSwitches.upCount)",
                "variant_switch_down=\(monitor.variantSwitches.downCount)",
                "variant_switch_lateral=\(monitor.variantSwitches.lateralCount)",
                "variant_switch_unknown_direction=\(monitor.variantSwitches.unknownDirectionCount)",
                "variant_switch_latest_at=\(Self.optionalISO8601(monitor.variantSwitches.latestOccurredAt))",
                "variant_switch_latest_succeeded=\(monitor.variantSwitches.latestSucceeded.map(String.init) ?? "unknown")",
                "variant_switch_from_peak_bps=\(Self.decimal(monitor.variantSwitches.latestFrom?.peakBitRate))",
                "variant_switch_from_average_bps=\(Self.decimal(monitor.variantSwitches.latestFrom?.averageBitRate))",
                "variant_switch_from_resolution=\(Self.singleLine(monitor.variantSwitches.latestFrom?.resolution ?? "unknown"))",
                "variant_switch_from_fps=\(Self.decimal(monitor.variantSwitches.latestFrom?.frameRate))",
                "variant_switch_to_peak_bps=\(Self.decimal(monitor.variantSwitches.latestTo?.peakBitRate))",
                "variant_switch_to_average_bps=\(Self.decimal(monitor.variantSwitches.latestTo?.averageBitRate))",
                "variant_switch_to_resolution=\(Self.singleLine(monitor.variantSwitches.latestTo?.resolution ?? "unknown"))",
                "variant_switch_to_fps=\(Self.decimal(monitor.variantSwitches.latestTo?.frameRate))",
                "initial_wait_count=\(monitor.waiting.initialWaitCount)",
                "post_start_wait_count=\(monitor.waiting.postStartWaitCount)",
                "seek_wait_count=\(monitor.waiting.seekWaitCount)",
                "current_wait_kind=\(monitor.waiting.currentKind?.rawValue ?? "none")",
                "current_wait_seconds=\(Self.decimal(monitor.waiting.currentWaitDuration))",
                "total_wait_seconds=\(Self.decimal(monitor.waiting.totalWaitDuration))",
                "longest_wait_seconds=\(Self.decimal(monitor.waiting.longestWaitDuration))",
                "last_wait_seconds=\(Self.decimal(monitor.waiting.lastWaitDuration))",
                "last_wait_kind=\(monitor.waiting.lastKind?.rawValue ?? "none")",
                "last_wait_reason=\(Self.singleLine(monitor.waiting.lastReason ?? "none"))",
                "last_wait_ended_at=\(Self.optionalISO8601(monitor.waiting.lastEndedAt))",
                "slow_delivery_audio_count=\(monitor.slowDelivery.audioCount)",
                "slow_delivery_video_count=\(monitor.slowDelivery.videoCount)",
                "slow_delivery_muxed_count=\(monitor.slowDelivery.muxedCount)",
                "slow_delivery_unknown_count=\(monitor.slowDelivery.unknownCount)",
                "slow_delivery_worst_audio_ratio=\(Self.decimal(monitor.slowDelivery.worstAudioRatio))",
                "slow_delivery_worst_video_ratio=\(Self.decimal(monitor.slowDelivery.worstVideoRatio))",
                "slow_delivery_worst_muxed_ratio=\(Self.decimal(monitor.slowDelivery.worstMuxedRatio))",
                "slow_delivery_worst_unknown_ratio=\(Self.decimal(monitor.slowDelivery.worstUnknownRatio))",
                "slow_delivery_latest_at=\(Self.optionalISO8601(monitor.slowDelivery.latestOccurredAt))",
                "slow_delivery_latest_media=\(monitor.slowDelivery.latestMediaType?.rawValue ?? "unknown")",
                "classifier_candidates=\(monitor.classifier.candidateCount)",
                "classifier_emitted=\(monitor.classifier.emittedCount)",
                "classifier_suppressed=\(monitor.classifier.suppressedCount)",
                "classifier_sample_cap=\(monitor.classifier.sampleCap)",
                "classifier_sample_cap_reached=\(monitor.classifier.sampleCapReached)",
                "request_trace_received=\(monitor.requestTrace.receivedCount)",
                "request_trace_retained=\(monitor.requestTrace.entries.count)",
                "request_trace_dropped=\(monitor.requestTrace.droppedCount)"
            ])

            if let summary = monitor.playbackSummary {
                lines.append(
                    "playback_summary=\(Self.iso8601(summary.occurredAt)) " +
                    "error_domain=\(Self.singleLine(summary.error?.domain ?? "none")) " +
                    "error_code=\(summary.error.map { String($0.code) } ?? "none") " +
                    "error_recovered=\(summary.errorDidRecover.map(String.init) ?? "unknown") " +
                    "recoverable_errors=\(Self.integer(summary.recoverableErrorCount)) " +
                    "stalls=\(Self.integer(summary.stallCount)) " +
                    "variant_switches=\(Self.integer(summary.variantSwitchCount)) " +
                    "playback_seconds=\(Self.integer(summary.playbackDuration)) " +
                    "media_requests=\(Self.integer(summary.mediaResourceRequestCount)) " +
                    "stall_recovery_seconds=\(Self.decimal(summary.timeSpentRecoveringFromStall)) " +
                    "initial_startup_seconds=\(Self.decimal(summary.timeSpentInInitialStartup)) " +
                    "weighted_average_bitrate_bps=\(Self.integer(summary.timeWeightedAverageBitrate)) " +
                    "weighted_peak_bitrate_bps=\(Self.integer(summary.timeWeightedPeakBitrate))"
                )
            }

            if let failure = monitor.terminalFailure {
                lines.append(
                    "terminal_failure=\(Self.iso8601(failure.occurredAt)) " +
                    "position=\(Self.decimal(failure.mediaTime)) " +
                    "domain=\(Self.singleLine(failure.error.domain ?? "none")) code=\(failure.error.code)"
                )
            }

            if let context = monitor.latestFailureContext {
                lines.append(
                    "latest_request_failure=\(Self.iso8601(context.occurredAt)) " +
                    "signal=\(context.signalKind.rawValue) media=\(context.mediaType.rawValue) " +
                    "request_seconds=\(Self.decimal(context.requestDuration)) " +
                    "ttfb_seconds=\(Self.decimal(context.timeToFirstByte)) " +
                    "response_seconds=\(Self.decimal(context.responseDuration)) " +
                    "cache=\(context.wasReadFromCache.map(String.init) ?? "unknown") " +
                    "segment_seconds=\(Self.decimal(context.segmentDuration)) " +
                    "requested_byte_range_length=\(context.requestedByteRangeLength.map(String.init) ?? "unknown") " +
                    "response_body_bytes=\(context.responseBodyBytes.map(String.init) ?? "unknown") " +
                    "http_status=\(context.httpStatusCode.map(String.init) ?? "unknown") " +
                    "redirect_count=\(context.redirectCount.map(String.init) ?? "unknown") " +
                    "protocol=\(Self.singleLine(context.networkProtocol ?? "unknown")) " +
                    "dns_seconds=\(Self.decimal(context.dnsDuration)) " +
                    "connect_seconds=\(Self.decimal(context.connectDuration)) " +
                    "tls_seconds=\(Self.decimal(context.tlsDuration))"
                )
            }

            for (index, entry) in monitor.requestTrace.entries
                .sorted(by: Self.requestTraceSort)
                .enumerated() {
                lines.append(
                    "request_trace[\(index)]=at=\(Self.iso8601(entry.occurredAt)) " +
                    "kind=\(entry.kind.rawValue) media=\(entry.mediaType.rawValue) " +
                    "failed=\(entry.didFail) recovered=\(entry.didRecover.map(String.init) ?? "unknown") " +
                    "request_seconds=\(Self.decimal(entry.requestDuration)) " +
                    "ttfb_seconds=\(Self.decimal(entry.timeToFirstByte)) " +
                    "transfer_seconds=\(Self.decimal(entry.transferDuration)) " +
                    "http_status=\(entry.httpStatusCode.map(String.init) ?? "unknown") " +
                    "mime=\(entry.mimeCategory?.rawValue ?? "unknown") " +
                    "cache=\(entry.wasReadFromCache.map(String.init) ?? "unknown") " +
                    "redirects=\(entry.redirectCount.map(String.init) ?? "unknown") " +
                    "protocol=\(Self.singleLine(entry.networkProtocol ?? "unknown")) " +
                    "response_bytes=\(entry.responseBodyBytes.map(String.init) ?? "unknown") " +
                    "decoded_bytes=\(entry.decodedBodyBytes.map(String.init) ?? "unknown") " +
                    "reused=\(entry.reusedConnection.map(String.init) ?? "unknown") " +
                    "proxy=\(entry.proxyConnection.map(String.init) ?? "unknown") " +
                    "constrained=\(entry.constrainedNetwork.map(String.init) ?? "unknown") " +
                    "expensive=\(entry.expensiveNetwork.map(String.init) ?? "unknown") " +
                    "cellular=\(entry.cellularNetwork.map(String.init) ?? "unknown") " +
                    "multipath=\(entry.multipathConnection.map(String.init) ?? "unknown") " +
                    "fetch=\(entry.fetchType?.rawValue ?? "unknown") " +
                    "segment_delivery_ratio=\(Self.decimal(entry.segmentDeliveryRatio))"
                )
            }

            for (index, transition) in monitor.variantSwitches.recentTransitions
                .sorted(by: Self.variantTransitionSort)
                .enumerated() {
                lines.append(
                    "variant_transition[\(index)]=at=\(Self.iso8601(transition.occurredAt)) " +
                    "succeeded=\(transition.succeeded) " +
                    "from_peak_bps=\(Self.decimal(transition.from?.peakBitRate)) " +
                    "from_average_bps=\(Self.decimal(transition.from?.averageBitRate)) " +
                    "from_resolution=\(Self.singleLine(transition.from?.resolution ?? "unknown")) " +
                    "from_fps=\(Self.decimal(transition.from?.frameRate)) " +
                    "to_peak_bps=\(Self.decimal(transition.to.peakBitRate)) " +
                    "to_average_bps=\(Self.decimal(transition.to.averageBitRate)) " +
                    "to_resolution=\(Self.singleLine(transition.to.resolution ?? "unknown")) " +
                    "to_fps=\(Self.decimal(transition.to.frameRate))"
                )
            }
        }

        for (index, track) in audioTracks.sorted(by: Self.trackSort).enumerated() {
            lines.append(
                "audio_track[\(index)]=id=\(Self.singleLine(track.identifier ?? "unknown")) " +
                "language=\(Self.singleLine(track.languageCode ?? "unknown")) " +
                "selected=\(track.isSelected)"
            )
        }

        for (index, track) in subtitleTracks.sorted(by: Self.trackSort).enumerated() {
            lines.append(
                "subtitle_track[\(index)]=id=\(Self.singleLine(track.identifier ?? "unknown")) " +
                "language=\(Self.singleLine(track.languageCode ?? "unknown")) " +
                "selected=\(track.isSelected)"
            )
        }

        for (index, error) in recentErrors.sorted(by: Self.errorSort).enumerated() {
            lines.append(
                "error[\(index)]=at=\(Self.optionalISO8601(error.occurredAt)) " +
                "domain=\(Self.singleLine(error.domain ?? "none")) code=\(error.code)"
            )
        }

        for issue in issues().sorted(by: Self.issueSort) {
            lines.append(
                "issue[\(issue.level),\(issue.scope.rawValue)]=\(Self.singleLine(issue.title)): " +
                "\(Self.singleLine(issue.detail)) recommendation=\(Self.singleLine(issue.recommendation ?? "none"))"
            )
        }

        for event in recentHealthEvents.sorted(by: Self.healthEventSort) {
            lines.append(
                "event=\(Self.iso8601(event.occurredAt)) " +
                "signal=\(event.signalKind.rawValue) media=\(event.mediaType.rawValue) " +
                "confidence=\(event.confidence.rawValue) position=\(Self.decimal(event.mediaTime)) " +
                "domain=\(Self.singleLine(event.errorDomain ?? "none")) code=\(Self.integer(event.errorCode)) " +
                "recovered=\(event.didRecover.map(String.init) ?? "unknown") " +
                "track_id=\(Self.singleLine(event.selectedAudioTrack?.identifier ?? "unknown")) " +
                "track_language=\(Self.singleLine(event.selectedAudioTrack?.languageCode ?? "unknown"))"
            )
        }

        for sample in storyboard.samples.sorted(by: Self.sampleSort) {
            lines.append(
                "storyboard_sample=\(Self.iso8601(sample.capturedAt)) " +
                "id=\(sample.id.uuidString) " +
                "elapsed=\(Self.decimal(sample.sessionElapsed)) " +
                "position=\(Self.decimal(sample.mediaTime)) state=\(sample.state.rawValue) " +
                "waiting_reason=\(Self.singleLine(sample.waitingReason ?? "none")) " +
                "rate=\(Self.decimal(sample.playbackRate)) " +
                "likely_to_keep_up=\(sample.isPlaybackLikelyToKeepUp.map(String.init) ?? "unknown") " +
                "buffer_empty=\(sample.isPlaybackBufferEmpty.map(String.init) ?? "unknown") " +
                "buffer_full=\(sample.isPlaybackBufferFull.map(String.init) ?? "unknown") " +
                "buffer_headroom=\(Self.decimal(sample.bufferHeadroom)) " +
                "observed_bitrate_bps=\(Self.decimal(sample.observedBitRate)) " +
                "indicated_bitrate_bps=\(Self.decimal(sample.indicatedBitRate)) " +
                "resolution=\(Self.singleLine(sample.resolution ?? "unknown")) " +
                "frame_rate=\(Self.decimal(sample.frameRate)) " +
                "dropped_video_frames=\(Self.integer(sample.droppedVideoFrameCount)) " +
                "dropped_video_frame_delta=\(Self.integer(sample.droppedVideoFrameDelta)) " +
                "rendition_peak_bps=\(Self.decimal(sample.renditionPeakBitRate)) " +
                "rendition_average_bps=\(Self.decimal(sample.renditionAverageBitRate)) " +
                "rendition_resolution=\(Self.singleLine(sample.renditionResolution ?? "unknown")) " +
                "rendition_fps=\(Self.decimal(sample.renditionFrameRate)) " +
                "session_id=\(sample.sessionID?.uuidString ?? "unknown") " +
                "asset_id=\(Self.singleLine(sample.assetIdentifier ?? "unknown")) " +
                "availability=\(sample.availability.rawValue)"
            )
        }

        for evidence in storyboard.evidence.sorted(by: Self.evidenceSort) {
            lines.append(
                "storyboard_evidence=\(Self.iso8601(evidence.occurredAt)) " +
                "id=\(evidence.id.uuidString) kind=\(evidence.kind.rawValue) " +
                "level=\(String(describing: evidence.level)) " +
                "position=\(Self.decimal(evidence.mediaTime)) " +
                "title=\(Self.singleLine(evidence.title)) " +
                "measurement=\(Self.singleLine(evidence.measurement ?? "unknown"))"
            )
        }

        lines.append("[inferred]")
        for incident in storyboard.incidents.sorted(by: Self.incidentSort) {
            lines.append(
                "automatic_incident=\(Self.iso8601(incident.startedAt)) " +
                "id=\(incident.id.uuidString) kind=\(incident.kind.rawValue) " +
                "severity=\(String(describing: incident.severity)) state=\(incident.state.rawValue) " +
                "last_observed_at=\(Self.iso8601(incident.lastObservedAt)) " +
                "ended_at=\(Self.optionalISO8601(incident.endedAt)) " +
                "impact=\(Self.singleLine(incident.impact)) " +
                "likely_cause=\(Self.singleLine(incident.likelyCause)) " +
                "confidence=\(Self.singleLine(incident.evidenceStrength.rawValue)) " +
                "evidence_ids=\(incident.evidenceIDs.map(\.uuidString).sorted().joined(separator: ",")) " +
                "measured_values=\(Self.singleLine(incident.measuredValues.sorted().joined(separator: " | "))) " +
                "next_action=\(Self.singleLine(incident.nextAction))"
            )
        }

        lines.append("[operator_context]")
        for bookmark in storyboard.bookmarks.sorted(by: Self.bookmarkSort) {
            lines.append(
                "bookmark=\(Self.iso8601(bookmark.capturedAt)) id=\(bookmark.id.uuidString) " +
                "elapsed=\(Self.decimal(bookmark.sessionElapsed)) " +
                "position=\(Self.decimal(bookmark.mediaTime)) item=\(Self.singleLine(bookmark.itemStatus)) " +
                "time_control=\(Self.singleLine(bookmark.timeControlStatus)) " +
                "waiting_reason=\(Self.singleLine(bookmark.waitingReason ?? "none")) " +
                "buffer_headroom=\(Self.decimal(bookmark.bufferHeadroom)) " +
                "resolution=\(Self.singleLine(bookmark.resolution ?? "unknown")) " +
                "frame_rate=\(Self.decimal(bookmark.frameRate)) " +
                "observed_bitrate_bps=\(Self.decimal(bookmark.observedBitRate)) " +
                "indicated_bitrate_bps=\(Self.decimal(bookmark.indicatedBitRate)) " +
                "access_log_stalls=\(Self.integer(bookmark.accessLogStallCount)) " +
                "metric_stalls=\(Self.integer(bookmark.metricStallCount)) " +
                "hls_requests=\(Self.integer(bookmark.observedHLSRequestCount)) " +
                "failed_hls_requests=\(Self.integer(bookmark.failedHLSRequestCount)) " +
                "post_start_waits=\(Self.integer(bookmark.postStartWaitCount)) " +
                "seek_waits=\(Self.integer(bookmark.seekWaitCount)) " +
                "error_log_entries=\(bookmark.errorLogEventCount) " +
                "nearby_sample_ids=\(bookmark.nearbySampleIDs.map(\.uuidString).sorted().joined(separator: ",")) " +
                "nearby_evidence_ids=\(bookmark.nearbyEvidenceIDs.map(\.uuidString).sorted().joined(separator: ",")) " +
                "track_id=\(Self.singleLine(bookmark.selectedAudioTrack?.identifier ?? "unknown")) " +
                "track_language=\(Self.singleLine(bookmark.selectedAudioTrack?.languageCode ?? "unknown"))"
            )
        }

        return lines.joined(separator: "\n")
    }

    private func issue(
        _ id: String,
        _ level: PlaybackDiagnosticsLevel,
        _ scope: PlaybackDiagnosticsIssueScope,
        _ title: String,
        _ detail: String,
        _ recommendation: String?
    ) -> PlaybackDiagnosticsIssue {
        PlaybackDiagnosticsIssue(
            id: id,
            level: level,
            scope: scope,
            title: title,
            detail: detail,
            recommendation: recommendation
        )
    }

    private static func decimal(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "unknown" }
        return String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            value == 0 ? 0 : value
        )
    }

    private static func integer(_ value: Int?) -> String {
        value.map(String.init) ?? "unknown"
    }

    private static func available<T>(_ value: T, when isAvailable: Bool) -> String {
        isAvailable ? String(describing: value) : "unknown"
    }

    private static func interval(from start: Date?, to end: Date?) -> String {
        guard let start,
              let end,
              start.timeIntervalSinceReferenceDate.isFinite,
              end.timeIntervalSinceReferenceDate.isFinite else {
            return "unknown"
        }
        let value = end.timeIntervalSince(start)
        return value >= 0 ? decimal(value) : "unknown"
    }

    /// Shared because `report()` formats timestamps inside sort comparators and
    /// per-row loops. Allocating one of these per call cost thousands of
    /// formatter constructions per report and ran on the main thread.
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static func iso8601(_ date: Date) -> String {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return "unknown" }
        return iso8601Formatter.string(from: date)
    }

    private static func optionalISO8601(_ date: Date?) -> String {
        date.map(iso8601) ?? "unknown"
    }

    private static func singleLine(_ value: String) -> String {
        let normalized = value
            .unicodeScalars
            .filter { !CharacterSet.newlines.contains($0) && !CharacterSet.controlCharacters.contains($0) }
            .map(String.init)
            .joined()
        let lowercase = normalized.lowercased()
        let privacyMarkers = [
            "://",
            "authorization",
            "bearer ",
            "cookie=",
            "password=",
            "secret=",
            "signature=",
            "token=",
            "x-api-key",
        ]
        guard !privacyMarkers.contains(where: lowercase.contains),
              !normalized.contains("@") else {
            return "[redacted]"
        }
        // ponytail: report fields are intentionally compact; add structured
        // attachments instead of raising this ceiling if richer exports are needed.
        return String(normalized.prefix(512))
    }

    private static func trackSort(
        _ lhs: PlaybackDiagnosticsTrack,
        _ rhs: PlaybackDiagnosticsTrack
    ) -> Bool {
        sortKey([
            lhs.identifier ?? "",
            lhs.languageCode ?? "",
            String(lhs.isSelected),
        ]) < sortKey([
            rhs.identifier ?? "",
            rhs.languageCode ?? "",
            String(rhs.isSelected),
        ])
    }

    private static func errorSort(
        _ lhs: PlaybackDiagnosticsError,
        _ rhs: PlaybackDiagnosticsError
    ) -> Bool {
        sortKey([
            optionalISO8601(lhs.occurredAt),
            lhs.domain ?? "",
            String(lhs.code),
        ]) < sortKey([
            optionalISO8601(rhs.occurredAt),
            rhs.domain ?? "",
            String(rhs.code),
        ])
    }

    private static func errorRecencySort(
        _ lhs: PlaybackDiagnosticsError,
        _ rhs: PlaybackDiagnosticsError
    ) -> Bool {
        let lhsDate = lhs.occurredAt ?? .distantPast
        let rhsDate = rhs.occurredAt ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }
        return sortKey([lhs.domain ?? "", String(lhs.code)])
            < sortKey([rhs.domain ?? "", String(rhs.code)])
    }

    private static func issueSort(
        _ lhs: PlaybackDiagnosticsIssue,
        _ rhs: PlaybackDiagnosticsIssue
    ) -> Bool {
        if lhs.level != rhs.level {
            return lhs.level > rhs.level
        }
        return sortKey([lhs.title, lhs.id]) < sortKey([rhs.title, rhs.id])
    }

    private static func healthEventSort(
        _ lhs: PlaybackHealthEvent,
        _ rhs: PlaybackHealthEvent
    ) -> Bool {
        healthEventSortKey(lhs) < healthEventSortKey(rhs)
    }

    private static func healthEventSortKey(_ event: PlaybackHealthEvent) -> String {
        sortKey([
            iso8601(event.occurredAt),
            event.healthSessionID.uuidString,
            event.signalKind.rawValue,
            event.mediaType.rawValue,
            event.confidence.rawValue,
            decimal(event.mediaTime),
            event.errorDomain ?? "",
            integer(event.errorCode),
            event.didRecover.map(String.init) ?? "",
            event.selectedAudioTrack?.identifier ?? "",
            event.selectedAudioTrack?.languageCode ?? "",
        ])
    }

    private static func requestTraceSort(
        _ lhs: PlaybackHealthRequestTraceEntry,
        _ rhs: PlaybackHealthRequestTraceEntry
    ) -> Bool {
        requestTraceSortKey(lhs) < requestTraceSortKey(rhs)
    }

    private static func requestTraceSortKey(_ entry: PlaybackHealthRequestTraceEntry) -> String {
        sortKey([
            iso8601(entry.occurredAt),
            entry.kind.rawValue,
            entry.mediaType.rawValue,
            String(entry.didFail),
            entry.didRecover.map(String.init) ?? "",
            decimal(entry.requestDuration),
            decimal(entry.timeToFirstByte),
            decimal(entry.transferDuration),
            entry.httpStatusCode.map(String.init) ?? "",
            entry.mimeCategory?.rawValue ?? "",
            entry.wasReadFromCache.map(String.init) ?? "",
            entry.redirectCount.map(String.init) ?? "",
            entry.networkProtocol ?? "",
            entry.responseBodyBytes.map(String.init) ?? "",
            entry.decodedBodyBytes.map(String.init) ?? "",
            entry.reusedConnection.map(String.init) ?? "",
            entry.proxyConnection.map(String.init) ?? "",
            entry.constrainedNetwork.map(String.init) ?? "",
            entry.expensiveNetwork.map(String.init) ?? "",
            entry.cellularNetwork.map(String.init) ?? "",
            entry.multipathConnection.map(String.init) ?? "",
            entry.fetchType?.rawValue ?? "",
            decimal(entry.segmentDeliveryRatio),
        ])
    }

    private static func variantTransitionSort(
        _ lhs: PlaybackHealthVariantTransition,
        _ rhs: PlaybackHealthVariantTransition
    ) -> Bool {
        variantTransitionSortKey(lhs) < variantTransitionSortKey(rhs)
    }

    private static func variantTransitionSortKey(
        _ transition: PlaybackHealthVariantTransition
    ) -> String {
        sortKey([
            iso8601(transition.occurredAt),
            String(transition.succeeded),
            decimal(transition.from?.peakBitRate),
            decimal(transition.from?.averageBitRate),
            transition.from?.resolution ?? "",
            decimal(transition.from?.frameRate),
            decimal(transition.to.peakBitRate),
            decimal(transition.to.averageBitRate),
            transition.to.resolution ?? "",
            decimal(transition.to.frameRate),
        ])
    }

    /// Chronological, with the identifier as a deterministic tiebreak.
    ///
    /// These compare `Date` values directly rather than their ISO-8601
    /// renderings: formatting inside a comparator is both far more expensive
    /// and needlessly indirect, since string ordering here only happened to
    /// agree with time ordering because the format is fixed-width.
    private static func chronological(
        _ lhs: Date,
        _ rhs: Date,
        _ lhsID: UUID,
        _ rhsID: UUID
    ) -> Bool {
        if lhs != rhs {
            return lhs < rhs
        }
        return lhsID.uuidString < rhsID.uuidString
    }

    private static func sampleSort(
        _ lhs: PlaybackDiagnosticsSample,
        _ rhs: PlaybackDiagnosticsSample
    ) -> Bool {
        chronological(lhs.capturedAt, rhs.capturedAt, lhs.id, rhs.id)
    }

    private static func evidenceSort(
        _ lhs: PlaybackDiagnosticsEvidence,
        _ rhs: PlaybackDiagnosticsEvidence
    ) -> Bool {
        chronological(lhs.occurredAt, rhs.occurredAt, lhs.id, rhs.id)
    }

    private static func incidentSort(
        _ lhs: PlaybackDiagnosticsAutomaticIncident,
        _ rhs: PlaybackDiagnosticsAutomaticIncident
    ) -> Bool {
        chronological(lhs.startedAt, rhs.startedAt, lhs.id, rhs.id)
    }

    private static func bookmarkSort(
        _ lhs: PlaybackDiagnosticsBookmark,
        _ rhs: PlaybackDiagnosticsBookmark
    ) -> Bool {
        chronological(lhs.capturedAt, rhs.capturedAt, lhs.id, rhs.id)
    }

    private static func sortKey(_ fields: [String]) -> String {
        fields.joined(separator: "\u{1F}")
    }
}

private extension PlaybackHealthConfidence {
    var rank: Int {
        switch self {
        case .low:
            return 0
        case .medium:
            return 1
        case .high:
            return 2
        }
    }
}
#endif
