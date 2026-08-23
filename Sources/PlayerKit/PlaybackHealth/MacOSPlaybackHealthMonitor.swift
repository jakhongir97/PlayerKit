#if os(macOS)
@preconcurrency import AVFoundation
import CryptoKit
import Foundation
import OSLog

private let playbackHealthLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.netco.itv",
    category: "PlaybackHealth"
)

private let playbackHealthErrorDomainAllowlist: Set<String> = [
    "AVFoundationErrorDomain",
    "CoreMediaErrorDomain",
    "NSOSStatusErrorDomain",
    "NSURLErrorDomain",
    "kCFErrorDomainCFNetwork"
]

func sanitizedPlaybackHealthErrorDomain(_ errorDomain: String?) -> String? {
    guard let errorDomain,
          playbackHealthErrorDomainAllowlist.contains(errorDomain) else {
        return nil
    }

    return errorDomain
}

func sanitizedPlaybackHealthInterval(from start: Date, to end: Date) -> Double? {
    let duration = end.timeIntervalSince(start)
    guard duration.isFinite, duration >= 0 else { return nil }
    return duration
}

struct PlaybackHealthFailureFingerprintWindow {
    private struct Entry {
        let identity: Data
        let code: Int
        let occurredAt: Date
    }

    private let capacity: Int
    private let duplicateWindow: TimeInterval
    private var entries: [Entry] = []

    init(capacity: Int = 20, duplicateWindow: TimeInterval = 2) {
        self.capacity = max(capacity, 1)
        self.duplicateWindow = max(duplicateWindow, 0)
    }

    mutating func record(
        rawDomain: String?,
        rawResource: String?,
        code: Int,
        occurredAt: Date
    ) {
        guard let identity = Self.identity(
            rawDomain: rawDomain,
            rawResource: rawResource
        ) else {
            return
        }
        entries.append(Entry(identity: identity, code: code, occurredAt: occurredAt))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    mutating func consumeDuplicate(
        rawDomain: String?,
        rawResource: String?,
        code: Int,
        occurredAt: Date
    ) -> Bool {
        guard let identity = Self.identity(
            rawDomain: rawDomain,
            rawResource: rawResource
        ) else {
            return false
        }
        let matches = entries.indices.filter { index in
            let entry = entries[index]
            return entry.identity == identity
                && entry.code == code
                && abs(entry.occurredAt.timeIntervalSince(occurredAt)) <= duplicateWindow
        }
        // Multiple identical failures in the window are ambiguous; retaining a
        // possible duplicate is safer than suppressing a distinct incident.
        guard matches.count == 1, let index = matches.first else { return false }
        entries.remove(at: index)
        return true
    }

    private static func identity(
        rawDomain: String?,
        rawResource: String?
    ) -> Data? {
        guard let rawDomain,
              let rawResource,
              !rawDomain.isEmpty,
              !rawResource.isEmpty,
              let normalizedResource = normalizedResource(rawResource) else {
            return nil
        }
        let domainByteCount = rawDomain.utf8.count
        let resourceByteCount = normalizedResource.utf8.count
        guard domainByteCount <= 16_384,
              resourceByteCount <= 16_384 - domainByteCount else {
            return nil
        }
        let domainBytes = Data(rawDomain.utf8)
        let resourceBytes = Data(normalizedResource.utf8)

        var material = Data()
        for bytes in [domainBytes, resourceBytes] {
            var length = UInt64(bytes.count).bigEndian
            Swift.withUnsafeBytes(of: &length) {
                material.append(contentsOf: $0)
            }
            material.append(bytes)
        }
        return Data(SHA256.hash(data: material))
    }

    private static func normalizedResource(_ rawResource: String) -> String? {
        guard rawResource.utf8.count <= 16_384,
              let components = URLComponents(string: rawResource),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }
        let port = components.port.map { ":\($0)" } ?? ""
        let path = components.percentEncodedPath.isEmpty
            ? "/"
            : components.percentEncodedPath
        return host + port + path
    }
}

struct PlaybackHealthSignalSnapshot: Sendable, Equatable {
    let healthSessionID: UUID
    let signalKind: PlaybackHealthSignalKind
    let mediaType: PlaybackHealthMediaType
    let mediaTime: Double?
    let selectedAudioTrack: PlaybackHealthAudioTrack?
    let errorDomain: String?
    let errorCode: Int?
    let didRecover: Bool?
    let occurredAt: Date
}

actor MacOSPlaybackHealthClassifier {
    private struct CandidateKey: Hashable {
        let signalKind: PlaybackHealthSignalKind
        let mediaType: PlaybackHealthMediaType
        let selectedTrackIdentifier: String?
    }

    // ponytail: 200 unique samples bounds per-session calibration logs; a
    // calibrated correlation window can replace first-signal finalization later.
    static let calibrationSampleCap = 200

    let healthSessionID: UUID
    let assetIdentifier: String?

    private var isActive = true
    private var candidateCount = 0
    private var emittedCount = 0
    private var suppressedCount = 0
    private var didLogSampleCap = false
    private var emittedCandidateKeys: Set<CandidateKey> = []

    init(healthSessionID: UUID, assetIdentifier: String?) {
        self.healthSessionID = healthSessionID
        self.assetIdentifier = assetIdentifier
    }

    func classify(_ snapshot: PlaybackHealthSignalSnapshot) -> PlaybackHealthEvent? {
        candidateCount += 1

        guard isActive else {
            suppressedCount += 1
            playbackHealthLogger.debug("candidate suppressed reason=inactive")
            return nil
        }

        guard snapshot.healthSessionID == healthSessionID else {
            suppressedCount += 1
            playbackHealthLogger.debug("candidate suppressed reason=stale_session")
            return nil
        }

        guard emittedCount < Self.calibrationSampleCap else {
            suppressedCount += 1
            if !didLogSampleCap {
                didLogSampleCap = true
                playbackHealthLogger.info(
                    "calibration sample suppressed reason=session_cap cap=\(Self.calibrationSampleCap, privacy: .public)"
                )
            }
            return nil
        }

        guard let confidence = confidence(for: snapshot) else {
            suppressedCount += 1
            playbackHealthLogger.debug(
                "candidate suppressed reason=unsupported_media signal=\(snapshot.signalKind.rawValue, privacy: .public) media=\(snapshot.mediaType.rawValue, privacy: .public)"
            )
            return nil
        }

        let retainedAudioTrack = snapshot.selectedAudioTrack.map {
            PlaybackHealthAudioTrack(
                identifier: $0.identifier,
                languageCode: $0.languageCode,
                displayName: nil,
                isSelected: $0.isSelected
            )
        }
        let candidateKey = CandidateKey(
            signalKind: snapshot.signalKind,
            mediaType: snapshot.mediaType,
            selectedTrackIdentifier: retainedAudioTrack?.identifier
        )
        guard emittedCandidateKeys.insert(candidateKey).inserted else {
            suppressedCount += 1
            playbackHealthLogger.debug("candidate suppressed reason=session_duplicate")
            return nil
        }

        let sanitizedDomain = sanitizedPlaybackHealthErrorDomain(snapshot.errorDomain)
        emittedCount += 1
        playbackHealthLogger.debug(
            "calibration sample emitted signal=\(snapshot.signalKind.rawValue, privacy: .public) confidence=\(confidence.rawValue, privacy: .public) media=\(snapshot.mediaType.rawValue, privacy: .public) position=\(self.sanitizedMediaTime(snapshot.mediaTime) ?? -1, privacy: .private) domain=\(sanitizedDomain ?? "none", privacy: .private) code=\(snapshot.errorCode ?? 0, privacy: .private) recovered=\(snapshot.didRecover?.description ?? "unknown", privacy: .private)"
        )

        return PlaybackHealthEvent(
            healthSessionID: healthSessionID,
            assetIdentifier: assetIdentifier,
            signalKind: snapshot.signalKind,
            confidence: confidence,
            mediaType: snapshot.mediaType,
            mediaTime: sanitizedMediaTime(snapshot.mediaTime),
            selectedAudioTrack: retainedAudioTrack,
            errorDomain: sanitizedDomain,
            errorCode: snapshot.errorCode,
            didRecover: snapshot.didRecover,
            occurredAt: snapshot.occurredAt
        )
    }

    func invalidate() {
        playbackHealthLogger.info(
            "monitor summary candidates=\(self.candidateCount, privacy: .public) emitted=\(self.emittedCount, privacy: .public) suppressed=\(self.suppressedCount, privacy: .public)"
        )
        isActive = false
    }

    func telemetry() -> PlaybackHealthClassifierTelemetry {
        PlaybackHealthClassifierTelemetry(
            candidateCount: candidateCount,
            emittedCount: emittedCount,
            suppressedCount: suppressedCount,
            sampleCap: Self.calibrationSampleCap
        )
    }

    private func confidence(for snapshot: PlaybackHealthSignalSnapshot) -> PlaybackHealthConfidence? {
        switch snapshot.signalKind {
        case .playbackStall, .errorLogEntry:
            return .low
        case .contentKeyRequestFailure:
            return nil
        case .playlistRequestFailure, .mediaSegmentRequestFailure:
            switch snapshot.mediaType {
            case .audio:
                return snapshot.didRecover == false ? .high : .medium
            case .muxed, .unknown:
                return .medium
            case .video:
                return .low
            }
        }
    }

    private func sanitizedMediaTime(_ mediaTime: Double?) -> Double? {
        guard let mediaTime, mediaTime.isFinite, mediaTime >= 0 else {
            return nil
        }

        return (mediaTime * 10).rounded() / 10
    }
}

// The monitor is intentionally multi-queue: mutable telemetry is guarded by
// `stateLock`, error-log parsing is serialized by `errorLogQueue`, and emitted
// events cross back through an explicitly main-actor callback. AVFoundation's
// reference types predate Sendable annotations, so this conformance records the
// synchronization the implementation already enforces.
final class MacOSPlaybackHealthMonitor: @unchecked Sendable {
    private static let naturalEndResumeThreshold: TimeInterval = 1
    private static let stallDuplicateWindow: TimeInterval = 2
    private static let stallFingerprintCapacity = 8

    private struct StallFingerprint {
        let occurredAt: Date
        let mediaTime: Double?
    }

    let healthSessionID: UUID
    let assetIdentifier: String?

    private let classifier: MacOSPlaybackHealthClassifier
    private let selectedAudioTrackProvider:
        @MainActor @Sendable () async -> PlaybackHealthAudioTrack?
    private let eventHandler: @MainActor (PlaybackHealthEvent) -> Void
    private weak var monitoredItem: AVPlayerItem?
    private let errorLogQueue = DispatchQueue(
        label: "com.netco.itv.playback-health.error-log"
    )

    // ponytail: AVPlayerWrapper owns load/stop lifecycle on the main thread.
    // Move all monitor lifecycle state into an actor before permitting background mutation.
    private var metricTask: Task<Void, Never>?
    private var errorLogObserver: NSObjectProtocol?
    private var processedErrorLogEntryCount = 0
    private let stateLock = NSLock()
    private var _isStopped = false
    private var _telemetry: PlaybackHealthMonitorTelemetry
    private var waitStartedUptime: TimeInterval?
    private var completedWaitDuration: TimeInterval = 0
    private var hasReachedPlaying = false
    private var stallFingerprints: [StallFingerprint] = []
    // ponytail: a 20-entry, two-second SHA-256 identity window bridges AVMetrics
    // to the error log; replace it with a platform correlation ID if Apple exposes one.
    private var typedMetricFailureFingerprints = PlaybackHealthFailureFingerprintWindow()

    init(
        item: AVPlayerItem,
        healthSessionID: UUID = UUID(),
        assetIdentifier: String?,
        selectedAudioTrackProvider:
            @escaping @MainActor @Sendable () async -> PlaybackHealthAudioTrack?,
        eventHandler: @escaping @MainActor (PlaybackHealthEvent) -> Void
    ) {
        let initialStreamState: PlaybackHealthMonitorStreamState
        if #available(macOS 15, *) {
            initialStreamState = .starting
        } else {
            initialStreamState = .fallbackObserving
        }
        self.healthSessionID = healthSessionID
        self.assetIdentifier = assetIdentifier
        self._telemetry = .initial(for: initialStreamState)
        self.classifier = MacOSPlaybackHealthClassifier(
            healthSessionID: healthSessionID,
            assetIdentifier: assetIdentifier
        )
        self.monitoredItem = item
        self.selectedAudioTrackProvider = selectedAudioTrackProvider
        self.eventHandler = eventHandler

        startErrorLogObservation(for: item)
        if #available(macOS 15, *) {
            playbackHealthLogger.info(
                "monitor attached path=avmetrics asset_present=\(assetIdentifier != nil, privacy: .public)"
            )
            startMetrics(for: item)
        } else {
            playbackHealthLogger.info(
                "monitor attached path=error_log asset_present=\(assetIdentifier != nil, privacy: .public)"
            )
        }
    }

    deinit {
        stop()
    }

    func stop() {
        stateLock.lock()
        guard !_isStopped else {
            stateLock.unlock()
            return
        }
        _isStopped = true
        if _telemetry.streamState != .failed {
            _telemetry.streamState = .ended
        }
        stateLock.unlock()

        playbackHealthLogger.info("monitor detached")
        metricTask?.cancel()
        metricTask = nil

        if let errorLogObserver {
            NotificationCenter.default.removeObserver(errorLogObserver)
            self.errorLogObserver = nil
        }

        // Capture the actor, not `self`. Reading `self.classifier` inside the
        // Task retains a strong reference to the monitor, and `stop()` is also
        // reachable from `deinit` — resurrecting a deallocating object, which
        // traps with "deallocated with non-zero retain count".
        let classifier = self.classifier
        Task.detached {
            await classifier.invalidate()
        }
    }

    var telemetrySnapshot: PlaybackHealthMonitorTelemetry {
        telemetrySnapshot(atSystemUptime: ProcessInfo.processInfo.systemUptime)
    }

    func telemetrySnapshot(
        atSystemUptime systemUptime: TimeInterval
    ) -> PlaybackHealthMonitorTelemetry {
        stateLock.lock()
        defer { stateLock.unlock() }
        var snapshot = _telemetry
        if let waitStartedUptime {
            let currentDuration = max(systemUptime - waitStartedUptime, 0)
            snapshot.waiting.currentWaitDuration = currentDuration
            snapshot.waiting.totalWaitDuration = completedWaitDuration + currentDuration
            snapshot.waiting.longestWaitDuration = max(
                snapshot.waiting.longestWaitDuration,
                currentDuration
            )
        } else {
            snapshot.waiting.currentWaitDuration = nil
            snapshot.waiting.totalWaitDuration = completedWaitDuration
        }
        return snapshot
    }

    @available(macOS 15, *)
    private func startMetrics(for item: AVPlayerItem) {
        metricTask = Task { [weak self, weak item] in
            guard let item else { return }
            defer {
                if self?.finishMetricsStream(cancelled: Task.isCancelled) == true {
                    self?.scheduleErrorLogConsumption(for: item)
                }
                let healthyDropCount = self?.telemetrySnapshot.healthyDropCount ?? 0
                playbackHealthLogger.info(
                    "metric stream ended healthy_dropped=\(healthyDropCount, privacy: .public)"
                )
            }

            do {
                let stream = item.metrics(forType: AVMetricHLSMediaSegmentRequestEvent.self)
                    .chronologicalMerge(
                        with: item.metrics(forType: AVMetricHLSPlaylistRequestEvent.self),
                        item.metrics(forType: AVMetricPlayerItemStallEvent.self),
                        item.metrics(forType: AVMetricPlayerItemVariantSwitchEvent.self),
                        item.metrics(forType: AVMetricContentKeyRequestEvent.self),
                        item.metrics(forType: AVMetricPlayerItemLikelyToKeepUpEvent.self),
                        item.metrics(forType: AVMetricPlayerItemSeekEvent.self),
                        item.metrics(forType: AVMetricPlayerItemSeekDidCompleteEvent.self),
                        item.metrics(forType: AVMetricPlayerItemPlaybackSummaryEvent.self)
                    )
                self?.beginTypedObservation(for: item)

                for try await (event, _) in stream {
                    guard !Task.isCancelled else { return }
                    guard let self else { return }

                    if let segment = event as? AVMetricHLSMediaSegmentRequestEvent {
                        let resource = segment.mediaResourceRequestEvent
                        let metricError = resource?.errorEvent
                        let mediaType = playbackHealthMediaType(segment.mediaType)
                        // ponytail: Apple added this getter with macOS 26, but the
                        // 26.2 SDK omits its property-level availability annotation.
                        // Calling it on macOS 15 aborts with an unrecognized selector;
                        // keep the rest of AVMetrics and omit only this optional field.
                        let segmentDuration: Double?
                        if #available(macOS 26, *) {
                            segmentDuration = segment.segmentDuration
                        } else {
                            segmentDuration = nil
                        }
                        recordMetricRequest(
                            kind: .segment,
                            mediaType: mediaType,
                            clientInitiated: false,
                            segmentDuration: segmentDuration,
                            occurredAt: segment.date,
                            resource: resource
                        )
                        guard let metricError else { continue }
                        let failure = await metricSnapshot(
                            signalKind: .mediaSegmentRequestFailure,
                            mediaType: segment.mediaType,
                            mediaTime: segment.mediaTime.seconds,
                            metricError: metricError
                        )
                        recordTypedMetricFailure(
                            failure,
                            rawDomain: (metricError.error as NSError).domain,
                            rawResource: resource?.url?.absoluteString
                        )
                        await consume(failure)
                    } else if let playlist = event as? AVMetricHLSPlaylistRequestEvent {
                        let resource = playlist.mediaResourceRequestEvent
                        let metricError = resource?.errorEvent
                        let mediaType = playbackHealthMediaType(playlist.mediaType)
                        recordMetricRequest(
                            kind: .playlist,
                            mediaType: mediaType,
                            clientInitiated: false,
                            segmentDuration: nil,
                            occurredAt: playlist.date,
                            resource: resource
                        )
                        guard let metricError else { continue }
                        let failure = await metricSnapshot(
                            signalKind: .playlistRequestFailure,
                            mediaType: playlist.mediaType,
                            mediaTime: playlist.mediaTime.seconds,
                            metricError: metricError
                        )
                        recordTypedMetricFailure(
                            failure,
                            rawDomain: (metricError.error as NSError).domain,
                            rawResource: resource?.url?.absoluteString
                        )
                        await consume(failure)
                    } else if let contentKey = event as? AVMetricContentKeyRequestEvent {
                        let resource = contentKey.mediaResourceRequestEvent
                        let metricError = resource?.errorEvent
                        let mediaType = playbackHealthMediaType(contentKey.mediaType)
                        recordMetricRequest(
                            kind: .contentKey,
                            mediaType: mediaType,
                            clientInitiated: contentKey.isClientInitiated,
                            segmentDuration: nil,
                            occurredAt: contentKey.date,
                            resource: resource
                        )
                        guard let metricError else { continue }
                        let nsError = metricError.error as NSError
                        let failure = PlaybackHealthSignalSnapshot(
                            healthSessionID: healthSessionID,
                            signalKind: .contentKeyRequestFailure,
                            mediaType: mediaType,
                            mediaTime: contentKey.mediaTime.seconds,
                            selectedAudioTrack: nil,
                            errorDomain: nsError.domain,
                            errorCode: nsError.code,
                            didRecover: metricError.didRecover,
                            occurredAt: metricError.date
                        )
                        recordTypedMetricFailure(
                            failure,
                            rawDomain: nsError.domain,
                            rawResource: resource?.url?.absoluteString
                        )
                    } else if let likelyToKeepUp = event as? AVMetricPlayerItemLikelyToKeepUpEvent {
                        recordLikelyToKeepUp(likelyToKeepUp)
                    } else if let seekCompleted = event as? AVMetricPlayerItemSeekDidCompleteEvent {
                        recordSeekCompleted(
                            didSeekInBuffer: seekCompleted.didSeekInBuffer,
                            occurredAt: seekCompleted.date
                        )
                    } else if let seekStarted = event as? AVMetricPlayerItemSeekEvent {
                        recordSeekStarted(occurredAt: seekStarted.date)
                    } else if let summary = event as? AVMetricPlayerItemPlaybackSummaryEvent {
                        recordPlaybackSummary(summary)
                    } else if let stall = event as? AVMetricPlayerItemStallEvent {
                        let mediaTime = stall.mediaTime.seconds
                        guard recordPlaybackStallIfNew(
                            mediaTime: mediaTime,
                            occurredAt: stall.date
                        ) else {
                            continue
                        }
                        await consume(
                            PlaybackHealthSignalSnapshot(
                                healthSessionID: healthSessionID,
                                signalKind: .playbackStall,
                                mediaType: .unknown,
                                mediaTime: mediaTime,
                                selectedAudioTrack: await selectedAudioTrackProvider(),
                                errorDomain: nil,
                                errorCode: nil,
                                didRecover: nil,
                                occurredAt: stall.date
                            )
                        )
                    } else if let variantSwitch = event as? AVMetricPlayerItemVariantSwitchEvent {
                        recordVariantSwitch(variantSwitch)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                let nsError = error as NSError
                let domain = sanitizedPlaybackHealthErrorDomain(nsError.domain)
                updateTelemetry { telemetry in
                    telemetry.streamState = .fallbackObserving
                    telemetry.fallbackReason = .metricsFailed
                    telemetry.streamFailure = PlaybackDiagnosticsError(
                        occurredAt: Date(),
                        domain: domain,
                        code: nsError.code
                    )
                }
                scheduleErrorLogConsumption(for: item)
                playbackHealthLogger.error(
                    "metric stream failed domain=\(domain ?? "unlisted", privacy: .private) code=\(nsError.code, privacy: .private)"
                )
            }
        }
    }

    @available(macOS 15, *)
    private func recordMetricRequest(
        kind: PlaybackHealthRequestKind,
        mediaType: PlaybackHealthMediaType,
        clientInitiated: Bool,
        segmentDuration: Double?,
        occurredAt: Date,
        resource: AVMetricMediaResourceRequestEvent?
    ) {
        let metricError = resource?.errorEvent
        let failed = metricError != nil
        let requestDuration = resource.flatMap {
            sanitizedPlaybackHealthInterval(from: $0.requestStartTime, to: $0.requestEndTime)
        }
        let signalKind: PlaybackHealthSignalKind
        switch kind {
        case .playlist:
            signalKind = .playlistRequestFailure
        case .segment:
            signalKind = .mediaSegmentRequestFailure
        case .contentKey:
            signalKind = .contentKeyRequestFailure
        }
        let failureContext = metricError.map {
            requestFailureContext(
                signalKind: signalKind,
                mediaType: mediaType,
                resource: resource,
                segmentDuration: segmentDuration,
                occurredAt: $0.date
            )
        }
        let traceEntry = requestTraceEntry(
            kind: kind,
            mediaType: mediaType,
            occurredAt: occurredAt,
            segmentDuration: segmentDuration,
            resource: resource
        )

        updateTelemetry { telemetry in
            switch kind {
            case .playlist:
                telemetry.playlistRequestCount += 1
                if failed {
                    telemetry.failedPlaylistRequestCount += 1
                } else {
                    telemetry.healthyPlaylistRequestCount += 1
                }
            case .segment:
                telemetry.segmentRequestCount += 1
                if failed {
                    telemetry.failedSegmentRequestCount += 1
                } else {
                    telemetry.healthySegmentRequestCount += 1
                }
            case .contentKey:
                telemetry.contentKeys.record(
                    mediaType: mediaType,
                    failed: failed,
                    clientInitiated: clientInitiated
                )
            }

            if kind != .contentKey {
                switch mediaType {
                case .audio:
                    telemetry.audioRequestCount += 1
                case .video:
                    telemetry.videoRequestCount += 1
                case .muxed:
                    telemetry.muxedRequestCount += 1
                case .unknown:
                    telemetry.unknownRequestCount += 1
                }
            }

            if let failureContext {
                telemetry.latestFailureContext = failureContext
            }
            telemetry.requestTrace.record(traceEntry)

            guard kind == .segment,
                  let requestDuration,
                  let segmentDuration,
                  requestDuration.isFinite,
                  segmentDuration.isFinite,
                  requestDuration > segmentDuration,
                  segmentDuration > 0 else {
                return
            }

            let ratio = requestDuration / segmentDuration
            telemetry.slowDelivery.latestOccurredAt = occurredAt
            telemetry.slowDelivery.latestMediaType = mediaType
            switch mediaType {
            case .audio:
                telemetry.slowDelivery.audioCount += 1
                telemetry.slowDelivery.worstAudioRatio = max(
                    telemetry.slowDelivery.worstAudioRatio ?? 0,
                    ratio
                )
            case .video:
                telemetry.slowDelivery.videoCount += 1
                telemetry.slowDelivery.worstVideoRatio = max(
                    telemetry.slowDelivery.worstVideoRatio ?? 0,
                    ratio
                )
            case .muxed:
                telemetry.slowDelivery.muxedCount += 1
                telemetry.slowDelivery.worstMuxedRatio = max(
                    telemetry.slowDelivery.worstMuxedRatio ?? 0,
                    ratio
                )
            case .unknown:
                telemetry.slowDelivery.unknownCount += 1
                telemetry.slowDelivery.worstUnknownRatio = max(
                    telemetry.slowDelivery.worstUnknownRatio ?? 0,
                    ratio
                )
            }
        }
    }

    @available(macOS 15, *)
    private func requestTraceEntry(
        kind: PlaybackHealthRequestKind,
        mediaType: PlaybackHealthMediaType,
        occurredAt: Date,
        segmentDuration: Double?,
        resource: AVMetricMediaResourceRequestEvent?
    ) -> PlaybackHealthRequestTraceEntry {
        let taskMetrics = resource?.networkTransactionMetrics
        let transaction = taskMetrics?.transactionMetrics.last
        let response = transaction?.response as? HTTPURLResponse
        let requestDuration = resource.flatMap {
            sanitizedPlaybackHealthInterval(from: $0.requestStartTime, to: $0.requestEndTime)
        }
        let safeSegmentDuration = sanitizedPositiveInterval(segmentDuration)
        let segmentDeliveryRatio = requestDuration.flatMap { requestDuration in
            safeSegmentDuration.map { requestDuration / $0 }
        }

        return PlaybackHealthRequestTraceEntry(
            kind: kind,
            mediaType: mediaType,
            occurredAt: occurredAt,
            didFail: resource?.errorEvent != nil,
            didRecover: resource?.errorEvent?.didRecover,
            requestDuration: requestDuration,
            timeToFirstByte: resource.flatMap {
                sanitizedPlaybackHealthInterval(from: $0.requestStartTime, to: $0.responseStartTime)
            },
            transferDuration: resource.flatMap {
                sanitizedPlaybackHealthInterval(from: $0.responseStartTime, to: $0.responseEndTime)
            },
            httpStatusCode: response.flatMap {
                (100...599).contains($0.statusCode) ? $0.statusCode : nil
            },
            mimeCategory: playbackHealthMIMECategory(response?.mimeType),
            wasReadFromCache: resource?.wasReadFromCache,
            redirectCount: taskMetrics.map { Int($0.redirectCount) },
            networkProtocol: sanitizedNetworkProtocol(transaction?.networkProtocolName),
            responseBodyBytes: transaction.flatMap {
                $0.countOfResponseBodyBytesReceived >= 0
                    ? $0.countOfResponseBodyBytesReceived
                    : nil
            },
            decodedBodyBytes: transaction.flatMap {
                $0.countOfResponseBodyBytesAfterDecoding >= 0
                    ? $0.countOfResponseBodyBytesAfterDecoding
                    : nil
            },
            reusedConnection: transaction?.isReusedConnection,
            proxyConnection: transaction?.isProxyConnection,
            constrainedNetwork: transaction?.isConstrained,
            expensiveNetwork: transaction?.isExpensive,
            cellularNetwork: transaction?.isCellular,
            multipathConnection: transaction?.isMultipath,
            fetchType: transaction.map { playbackHealthFetchType($0.resourceFetchType) },
            segmentDeliveryRatio: segmentDeliveryRatio
        )
    }

    @available(macOS 15, *)
    private func requestFailureContext(
        signalKind: PlaybackHealthSignalKind,
        mediaType: PlaybackHealthMediaType,
        resource: AVMetricMediaResourceRequestEvent?,
        segmentDuration: Double?,
        occurredAt: Date
    ) -> PlaybackHealthRequestFailureContext {
        let taskMetrics = resource?.networkTransactionMetrics
        let transaction = taskMetrics?.transactionMetrics.last
        let response = transaction?.response as? HTTPURLResponse
        return PlaybackHealthRequestFailureContext(
            signalKind: signalKind,
            mediaType: mediaType,
            occurredAt: occurredAt,
            requestDuration: resource.flatMap {
                sanitizedPlaybackHealthInterval(from: $0.requestStartTime, to: $0.requestEndTime)
            },
            timeToFirstByte: resource.flatMap {
                sanitizedPlaybackHealthInterval(from: $0.requestStartTime, to: $0.responseStartTime)
            },
            responseDuration: resource.flatMap {
                sanitizedPlaybackHealthInterval(from: $0.responseStartTime, to: $0.responseEndTime)
            },
            wasReadFromCache: resource?.wasReadFromCache,
            segmentDuration: sanitizedPositiveInterval(segmentDuration),
            requestedByteRangeLength: resource.flatMap {
                $0.byteRange.length > 0 ? $0.byteRange.length : nil
            },
            responseBodyBytes: transaction.flatMap {
                $0.countOfResponseBodyBytesReceived >= 0
                    ? $0.countOfResponseBodyBytesReceived
                    : nil
            },
            httpStatusCode: response.flatMap {
                (100...599).contains($0.statusCode) ? $0.statusCode : nil
            },
            redirectCount: taskMetrics.map { Int($0.redirectCount) },
            networkProtocol: sanitizedNetworkProtocol(transaction?.networkProtocolName),
            dnsDuration: sanitizedOptionalPlaybackHealthInterval(
                from: transaction?.domainLookupStartDate,
                to: transaction?.domainLookupEndDate
            ),
            connectDuration: sanitizedOptionalPlaybackHealthInterval(
                from: transaction?.connectStartDate,
                to: transaction?.connectEndDate
            ),
            tlsDuration: sanitizedOptionalPlaybackHealthInterval(
                from: transaction?.secureConnectionStartDate,
                to: transaction?.secureConnectionEndDate
            )
        )
    }

    @available(macOS 15, *)
    private func recordLikelyToKeepUp(
        _ event: AVMetricPlayerItemLikelyToKeepUpEvent
    ) {
        let initialRequests = (event as? AVMetricPlayerItemInitialLikelyToKeepUpEvent).map {
            PlaybackHealthInitialRequestTelemetry(
                playlists: PlaybackHealthRequestTimingAggregate(
                    requestDurations: $0.playlistRequestEvents.map {
                        metricRequestDuration($0.mediaResourceRequestEvent)
                    }
                ),
                segments: PlaybackHealthRequestTimingAggregate(
                    requestDurations: $0.mediaSegmentRequestEvents.map {
                        metricRequestDuration($0.mediaResourceRequestEvent)
                    }
                ),
                contentKeys: PlaybackHealthRequestTimingAggregate(
                    requestDurations: $0.contentKeyRequestEvents.map {
                        metricRequestDuration($0.mediaResourceRequestEvent)
                    }
                )
            )
        }
        let loadedRangeDuration = playbackHealthLoadedRangeDuration(
            event.loadedTimeRanges
        )

        updateTelemetry {
            $0.likelyToKeepUp.record(
                occurredAt: event.date,
                mediaTime: event.mediaTime.seconds,
                timeTaken: event.timeTaken,
                loadedRangeDuration: loadedRangeDuration,
                initialRequests: initialRequests
            )
        }
    }

    @available(macOS 15, *)
    private func metricRequestDuration(
        _ resource: AVMetricMediaResourceRequestEvent?
    ) -> Double? {
        resource.flatMap {
            sanitizedPlaybackHealthInterval(
                from: $0.requestStartTime,
                to: $0.requestEndTime
            )
        }
    }

    private func playbackHealthLoadedRangeDuration(
        _ ranges: [CMTimeRange]
    ) -> Double? {
        guard !ranges.isEmpty else { return 0 }
        let intervals = ranges.compactMap { range -> ClosedRange<Double>? in
            let start = range.start.seconds
            let duration = range.duration.seconds
            guard start.isFinite, duration.isFinite, duration >= 0 else {
                return nil
            }
            return start ... (start + duration)
        }
        .sorted { $0.lowerBound < $1.lowerBound }
        guard var active = intervals.first else { return nil }
        var total = 0.0
        for interval in intervals.dropFirst() {
            if interval.lowerBound <= active.upperBound {
                active = active.lowerBound ... max(active.upperBound, interval.upperBound)
            } else {
                total += active.upperBound - active.lowerBound
                active = interval
            }
        }
        total += active.upperBound - active.lowerBound
        return total
    }

    @available(macOS 15, *)
    private func recordPlaybackSummary(
        _ event: AVMetricPlayerItemPlaybackSummaryEvent
    ) {
        let metricError = event.errorEvent
        let nsError = metricError?.error as NSError?
        let summary = PlaybackHealthPlaybackSummaryTelemetry(
            occurredAt: event.date,
            errorDomain: nsError?.domain,
            errorCode: nsError?.code,
            errorDidRecover: metricError?.didRecover,
            recoverableErrorCount: event.recoverableErrorCount,
            stallCount: event.stallCount,
            variantSwitchCount: event.variantSwitchCount,
            playbackDuration: event.playbackDuration,
            mediaResourceRequestCount: event.mediaResourceRequestCount,
            timeSpentRecoveringFromStall: event.timeSpentRecoveringFromStall,
            timeSpentInInitialStartup: event.timeSpentInInitialStartup,
            timeWeightedAverageBitrate: event.timeWeightedAverageBitrate,
            timeWeightedPeakBitrate: event.timeWeightedPeakBitrate
        )
        updateTelemetry { $0.playbackSummary = summary }
    }

    @available(macOS 15, *)
    private func recordVariantSwitch(_ event: AVMetricPlayerItemVariantSwitchEvent) {
        let from = event.fromVariant.map(playbackHealthVariant)
        let to = playbackHealthVariant(event.toVariant)

        updateTelemetry { telemetry in
            telemetry.variantSwitches.record(
                from: from,
                to: to,
                succeeded: event.didSucceed,
                occurredAt: event.date
            )
        }
    }

    @available(macOS 15, *)
    private func playbackHealthVariant(_ variant: AVAssetVariant) -> PlaybackHealthVariant {
        let size = variant.videoAttributes?.presentationSize
        return PlaybackHealthVariant(
            peakBitRate: sanitizedPositiveInterval(variant.peakBitRate),
            averageBitRate: sanitizedPositiveInterval(variant.averageBitRate),
            resolution: size.flatMap {
                sanitizedPlaybackDiagnosticsResolution(
                    width: Double($0.width),
                    height: Double($0.height)
                )
            },
            frameRate: sanitizedPlaybackDiagnosticsFrameRate(
                variant.videoAttributes?.nominalFrameRate
            )
        )
    }

    private func sanitizedNetworkProtocol(_ value: String?) -> String? {
        guard let normalized = value?.lowercased(),
              ["h3", "h2", "http/1.1", "http/1.0"].contains(normalized) else {
            return nil
        }
        return normalized
    }

    private func playbackHealthMIMECategory(
        _ value: String?
    ) -> PlaybackHealthMIMECategory? {
        guard let value = value?.lowercased() else { return nil }
        switch value {
        case "application/vnd.apple.mpegurl",
             "application/x-mpegurl",
             "audio/mpegurl",
             "audio/x-mpegurl":
            return .hlsPlaylist
        case "video/mp2t":
            return .transportStream
        case "application/mp4", "audio/mp4", "video/mp4":
            return .mp4
        case "text/html":
            return .html
        case "application/json", "text/json":
            return .json
        case "text/plain":
            return .text
        case "application/octet-stream":
            return .binary
        default:
            return .other
        }
    }

    private func playbackHealthFetchType(
        _ value: URLSessionTaskMetrics.ResourceFetchType
    ) -> PlaybackHealthResourceFetchType {
        switch value {
        case .unknown:
            return .unknown
        case .networkLoad:
            return .networkLoad
        case .serverPush:
            return .serverPush
        case .localCache:
            return .localCache
        @unknown default:
            return .unknown
        }
    }

    private func sanitizedOptionalPlaybackHealthInterval(
        from start: Date?,
        to end: Date?
    ) -> Double? {
        guard let start, let end else { return nil }
        return sanitizedPlaybackHealthInterval(from: start, to: end)
    }

    private func sanitizedPositiveInterval(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private func finishMetricsStream(cancelled: Bool) -> Bool {
        guard !cancelled else { return false }
        stateLock.lock()
        defer { stateLock.unlock() }
        guard _telemetry.streamState == .observing
                || _telemetry.streamState == .starting else {
            return false
        }
        _telemetry.streamState = .fallbackObserving
        _telemetry.fallbackReason = .metricsEnded
        return true
    }

    func recordPlaybackStall(for item: AVPlayerItem, occurredAt: Date = Date()) {
        guard item === monitoredItem else { return }
        let mediaTime = item.currentTime().seconds
        guard recordPlaybackStallIfNew(
            mediaTime: mediaTime,
            occurredAt: occurredAt
        ) else {
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let snapshot = PlaybackHealthSignalSnapshot(
                healthSessionID: healthSessionID,
                signalKind: .playbackStall,
                mediaType: .unknown,
                mediaTime: mediaTime,
                selectedAudioTrack: await selectedAudioTrackProvider(),
                errorDomain: nil,
                errorCode: nil,
                didRecover: nil,
                occurredAt: occurredAt
            )
            await consume(snapshot)
        }
    }

    private func recordPlaybackStallIfNew(
        mediaTime: Double?,
        occurredAt: Date
    ) -> Bool {
        let safeMediaTime = mediaTime.flatMap {
            $0.isFinite && $0 >= 0 ? $0 : nil
        }
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !_isStopped else { return false }

        let isDuplicate = stallFingerprints.contains { fingerprint in
            guard abs(occurredAt.timeIntervalSince(fingerprint.occurredAt))
                    <= Self.stallDuplicateWindow else {
                return false
            }
            guard let lhs = safeMediaTime,
                  let rhs = fingerprint.mediaTime else {
                return true
            }
            return abs(lhs - rhs) <= 0.5
        }
        guard !isDuplicate else { return false }

        stallFingerprints.append(
            StallFingerprint(
                occurredAt: occurredAt,
                mediaTime: safeMediaTime
            )
        )
        if stallFingerprints.count > Self.stallFingerprintCapacity {
            stallFingerprints.removeFirst(
                stallFingerprints.count - Self.stallFingerprintCapacity
            )
        }
        _telemetry.stallCount += 1
        _telemetry.latestStallAt = occurredAt
        return true
    }

    func recordTerminalPlaybackFailure(
        error: Error?,
        item: AVPlayerItem,
        occurredAt: Date = Date()
    ) {
        guard item === monitoredItem else { return }
        let nsError = error as NSError? ?? item.error as NSError?
        let mediaTime = item.currentTime().seconds
        updateTelemetry { telemetry in
            guard telemetry.terminalFailure == nil else { return }
            telemetry.terminalFailure = PlaybackHealthTerminalFailure(
                occurredAt: occurredAt,
                mediaTime: mediaTime.isFinite && mediaTime >= 0 ? mediaTime : nil,
                error: PlaybackDiagnosticsError(
                    occurredAt: occurredAt,
                    domain: sanitizedPlaybackHealthErrorDomain(nsError?.domain),
                    code: nsError?.code ?? -1
                )
            )
        }
    }

    func recordNaturalPlaybackEnd(
        for item: AVPlayerItem,
        occurredAt: Date = Date()
    ) {
        guard item === monitoredItem else { return }
        recordNaturalPlaybackEnd(
            mediaTime: item.currentTime().seconds,
            occurredAt: occurredAt
        )
    }

    func recordNaturalPlaybackEnd(
        mediaTime: Double?,
        occurredAt: Date = Date()
    ) {
        updateTelemetry { telemetry in
            telemetry.naturalEnd = PlaybackHealthNaturalEndEvidence(
                occurredAt: occurredAt,
                mediaTime: mediaTime.flatMap {
                    $0.isFinite && $0 >= 0 ? $0 : nil
                }
            )
        }
    }

    func recordSeekStarted(occurredAt: Date = Date()) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !_isStopped else { return }

        _telemetry.seeks.recordStarted(occurredAt: occurredAt)
        if waitStartedUptime != nil,
           _telemetry.waiting.currentKind == .postStart {
            _telemetry.waiting.postStartWaitCount = max(
                _telemetry.waiting.postStartWaitCount - 1,
                0
            )
            _telemetry.waiting.seekWaitCount += 1
            _telemetry.waiting.currentKind = .seek
        }
    }

    func recordSeekCompleted(
        didSeekInBuffer: Bool?,
        occurredAt: Date = Date()
    ) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !_isStopped else { return }
        _telemetry.seeks.recordCompleted(
            didSeekInBuffer: didSeekInBuffer,
            occurredAt: occurredAt
        )
    }

    func recordTimeControlStatus(
        _ status: AVPlayer.TimeControlStatus,
        waitingReason: String?,
        mediaTime: Double? = nil,
        occurredAt: Date = Date(),
        systemUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !_isStopped else { return }

        if status == .waitingToPlayAtSpecifiedRate || status == .playing,
           let naturalEnd = _telemetry.naturalEnd,
           occurredAt > naturalEnd.occurredAt,
           let recordedEnd = naturalEnd.mediaTime,
           let mediaTime,
           recordedEnd.isFinite,
           mediaTime.isFinite,
           mediaTime >= 0,
           recordedEnd - mediaTime >= Self.naturalEndResumeThreshold {
            _telemetry.naturalEnd = nil
        }

        if status == .waitingToPlayAtSpecifiedRate {
            guard waitStartedUptime == nil else {
                _telemetry.waiting.lastReason = waitingReason
                return
            }

            waitStartedUptime = systemUptime
            _telemetry.waiting.lastReason = waitingReason
            if _telemetry.seeks.inProgressCount > 0 {
                _telemetry.waiting.seekWaitCount += 1
                _telemetry.waiting.currentKind = .seek
            } else if hasReachedPlaying {
                _telemetry.waiting.postStartWaitCount += 1
                _telemetry.waiting.currentKind = .postStart
            } else {
                _telemetry.waiting.initialWaitCount += 1
                _telemetry.waiting.currentKind = .initial
            }
            return
        }

        if let waitStartedUptime {
            let duration = max(systemUptime - waitStartedUptime, 0)
            completedWaitDuration += duration
            _telemetry.waiting.currentWaitDuration = nil
            _telemetry.waiting.totalWaitDuration = completedWaitDuration
            _telemetry.waiting.longestWaitDuration = max(
                _telemetry.waiting.longestWaitDuration,
                duration
            )
            _telemetry.waiting.lastWaitDuration = duration
            _telemetry.waiting.lastEndedAt = occurredAt
            _telemetry.waiting.lastKind = _telemetry.waiting.currentKind
            _telemetry.waiting.currentKind = nil
            self.waitStartedUptime = nil
        }

        if status == .playing {
            hasReachedPlaying = true
        }
    }

    private func startErrorLogObservation(for item: AVPlayerItem) {
        errorLogObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.newErrorLogEntryNotification,
            object: item,
            queue: nil
        ) { [weak self, weak item] _ in
            guard let self, let item else { return }
            scheduleErrorLogConsumption(for: item)
        }
    }

    private func scheduleErrorLogConsumption(for item: AVPlayerItem) {
        errorLogQueue.async { [weak self, weak item] in
            guard let self,
                  let item,
                  item === monitoredItem,
                  !isStopped else {
                return
            }
            consumeNewErrorLogEntries(from: item)
        }
    }

    private func consumeNewErrorLogEntries(from item: AVPlayerItem) {
        let events = item.errorLog()?.events ?? []
        stateLock.lock()
        guard !_isStopped else {
            stateLock.unlock()
            return
        }
        let streamState = _telemetry.streamState
        if streamState == .starting {
            // Startup entries stay pending until the first typed metric proves
            // coverage or the stream hands them to fallback.
            stateLock.unlock()
            return
        }
        if streamState == .observing {
            // Typed observation owns steady-state failures. Advancing here keeps
            // fallback replay bounded to entries racing the state transition.
            processedErrorLogEntryCount = events.count
            stateLock.unlock()
            return
        }
        guard streamState == .fallbackObserving
                || streamState == .failed
                || streamState == .ended else {
            stateLock.unlock()
            return
        }
        guard events.count > processedErrorLogEntryCount else {
            processedErrorLogEntryCount = events.count
            stateLock.unlock()
            return
        }

        let newEvents = events.dropFirst(processedErrorLogEntryCount)
        processedErrorLogEntryCount = events.count
        stateLock.unlock()

        for event in newEvents {
            let occurredAt = event.date ?? Date()
            let domain = sanitizedPlaybackHealthErrorDomain(event.errorDomain)
            if consumeMatchingTypedFailureFingerprint(
                rawDomain: event.errorDomain,
                rawResource: event.uri,
                code: event.errorStatusCode,
                occurredAt: occurredAt
            ) {
                continue
            }
            let snapshot = PlaybackHealthSignalSnapshot(
                healthSessionID: healthSessionID,
                signalKind: .errorLogEntry,
                mediaType: .unknown,
                mediaTime: nil,
                selectedAudioTrack: nil,
                errorDomain: domain,
                errorCode: event.errorStatusCode,
                didRecover: nil,
                occurredAt: occurredAt
            )

            Task { [weak self] in
                await self?.consume(snapshot)
            }
        }
    }

    private func beginTypedObservation(for item: AVPlayerItem) {
        stateLock.lock()
        guard !_isStopped else {
            stateLock.unlock()
            return
        }
        _telemetry.streamState = .observing
        stateLock.unlock()

        errorLogQueue.async { [weak self, weak item] in
            guard let self,
                  let item,
                  item === monitoredItem,
                  !isStopped else {
                return
            }
            let baseline = item.errorLog()?.events.count ?? 0
            stateLock.lock()
            processedErrorLogEntryCount = max(
                processedErrorLogEntryCount,
                baseline
            )
            stateLock.unlock()
        }
    }

    private func recordTypedMetricFailure(
        _ snapshot: PlaybackHealthSignalSnapshot,
        rawDomain: String?,
        rawResource: String?
    ) {
        guard let code = snapshot.errorCode else { return }
        stateLock.lock()
        typedMetricFailureFingerprints.record(
            rawDomain: rawDomain,
            rawResource: rawResource,
            code: code,
            occurredAt: snapshot.occurredAt
        )
        stateLock.unlock()
    }

    private func consumeMatchingTypedFailureFingerprint(
        rawDomain: String?,
        rawResource: String?,
        code: Int,
        occurredAt: Date
    ) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return typedMetricFailureFingerprints.consumeDuplicate(
            rawDomain: rawDomain,
            rawResource: rawResource,
            code: code,
            occurredAt: occurredAt
        )
    }

    @available(macOS 15, *)
    private func metricSnapshot(
        signalKind: PlaybackHealthSignalKind,
        mediaType: AVMediaType,
        mediaTime: Double?,
        metricError: AVMetricErrorEvent
    ) async -> PlaybackHealthSignalSnapshot {
        let nsError = metricError.error as NSError

        return PlaybackHealthSignalSnapshot(
            healthSessionID: healthSessionID,
            signalKind: signalKind,
            mediaType: playbackHealthMediaType(mediaType),
            mediaTime: mediaTime,
            selectedAudioTrack: await selectedAudioTrackProvider(),
            errorDomain: nsError.domain,
            errorCode: nsError.code,
            didRecover: metricError.didRecover,
            occurredAt: metricError.date
        )
    }

    private func playbackHealthMediaType(_ mediaType: AVMediaType) -> PlaybackHealthMediaType {
        switch mediaType {
        case .audio:
            return .audio
        case .video:
            return .video
        case .muxed:
            return .muxed
        default:
            return .unknown
        }
    }

    private func consume(_ snapshot: PlaybackHealthSignalSnapshot) async {
        let event = await classifier.classify(snapshot)
        let classifierTelemetry = await classifier.telemetry()
        updateTelemetry { $0.classifier = classifierTelemetry }

        guard let event else {
            return
        }

        guard !isStopped else { return }
        await eventHandler(event)
    }

    private func updateTelemetry(
        _ update: (inout PlaybackHealthMonitorTelemetry) -> Void
    ) {
        stateLock.lock()
        guard !_isStopped else {
            stateLock.unlock()
            return
        }
        update(&_telemetry)
        stateLock.unlock()
    }

    private var isStopped: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isStopped
    }
}
#endif
