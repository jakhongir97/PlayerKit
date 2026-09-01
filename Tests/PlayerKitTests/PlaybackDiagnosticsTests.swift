#if os(macOS)
import CoreMedia
import Foundation
import XCTest
@testable import PlayerKit

@MainActor
final class PlaybackDiagnosticsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PlayerManager.shared.resetPlayer()
        PlayerManager.shared.isPlaybackHealthMonitoringEnabled = false
        PlayerManager.shared.onPlaybackHealthEvent = nil
    }

    override func tearDown() {
        PlayerManager.shared.isPlaybackHealthMonitoringEnabled = false
        PlayerManager.shared.onPlaybackHealthEvent = nil
        PlayerManager.shared.resetPlayer()
        super.tearDown()
    }

    func testCurrentStatusPresentationKeepsPlaybackStateAndActiveIssuesDistinct() {
        XCTAssertEqual(
            PlaybackDiagnosticsCurrentStatus.resolve(
                availability: .activeAVMetrics,
                itemStatus: "ready",
                timeControlStatus: "playing",
                highestActiveIssue: nil
            ),
            .noProblemDetected
        )
        XCTAssertEqual(
            PlaybackDiagnosticsCurrentStatus.resolve(
                availability: .activeAVMetrics,
                itemStatus: "ready",
                timeControlStatus: "waiting",
                highestActiveIssue: .observation
            ),
            .waiting
        )
        XCTAssertEqual(
            PlaybackDiagnosticsCurrentStatus.resolve(
                availability: .activeAVMetrics,
                itemStatus: "ready",
                timeControlStatus: "playing",
                highestActiveIssue: .warning
            ),
            .needsAttention(.warning)
        )
        XCTAssertEqual(
            PlaybackDiagnosticsCurrentStatus.resolve(
                availability: .activeAVMetrics,
                itemStatus: "failed",
                timeControlStatus: "waiting",
                highestActiveIssue: .warning
            ),
            .failed
        )
        XCTAssertEqual(
            PlaybackDiagnosticsCurrentStatus.resolve(
                availability: .noPlayerItem,
                itemStatus: "unavailable",
                timeControlStatus: "unavailable",
                highestActiveIssue: .critical
            ),
            .nothingPlaying
        )
        XCTAssertEqual(
            PlaybackDiagnosticsCurrentStatus.resolve(
                availability: .unsupportedBackend,
                itemStatus: "unavailable",
                timeControlStatus: "unavailable",
                highestActiveIssue: nil
            ),
            .detailsUnavailable
        )
        XCTAssertEqual(
            PlaybackDiagnosticsCurrentStatus.resolve(
                availability: .monitorNotAttached,
                itemStatus: "ready",
                timeControlStatus: "playing",
                highestActiveIssue: nil
            ),
            .checkLimited
        )
        XCTAssertEqual(
            PlaybackDiagnosticsCurrentStatus.resolve(
                availability: .failedAVMetrics,
                itemStatus: "ready",
                timeControlStatus: "playing",
                highestActiveIssue: nil
            ),
            .checkLimited
        )
    }

    func testDeepSnapshotSurfacesBufferNetworkAndAudioHealthConditions() {
        let event = healthEvent(confidence: .high, mediaType: .audio)
        let snapshot = makeSnapshot(
            playback: PlaybackDiagnosticsSnapshot.Playback(
                itemStatus: "ready",
                timeControlStatus: "playing",
                waitingReason: nil,
                rate: 1,
                currentTime: 20,
                duration: 120,
                bufferedUntil: 21,
                bufferHeadroom: 1,
                loadedRangeCount: 1,
                seekableRangeCount: 1,
                isPlaybackLikelyToKeepUp: false,
                isPlaybackBufferEmpty: false,
                isPlaybackBufferFull: false,
                automaticallyWaitsToMinimizeStalling: true,
                isMuted: false,
                volume: 1,
                playbackType: "VOD",
                isLikelyHLS: true,
                resolution: "1920×1080",
                frameRate: 24,
                preferredForwardBufferDuration: 0,
                preferredPeakBitRate: 0,
                preferredMaximumResolution: nil
            ),
            network: PlaybackDiagnosticsSnapshot.Network(
                accessLogEventCount: 1,
                mediaRequestCount: 12,
                numberOfStalls: 1,
                droppedVideoFrameCount: 4,
                overdueDownloadCount: 2,
                bytesTransferred: 2_000_000,
                transferDuration: 2,
                observedBitRate: 1_000_000,
                indicatedBitRate: 4_000_000,
                indicatedAverageBitRate: 4_000_000,
                averageVideoBitRate: 3_500_000,
                averageAudioBitRate: 128_000,
                observedBitRateStandardDeviation: 500_000,
                switchBitRate: nil,
                segmentsDownloadedDuration: 30,
                durationWatched: 20,
                startupTime: 1,
                serverAddressChangeCount: 0
            ),
            events: [event]
        )

        let issues = snapshot.issues()

        XCTAssertTrue(issues.contains(where: { $0.id == "low-buffer" }))
        XCTAssertTrue(issues.contains(where: { $0.id == "not-likely-to-keep-up" }))
        XCTAssertTrue(issues.contains(where: { $0.id == "throughput-shortfall" && $0.level == .warning }))
        XCTAssertTrue(issues.contains(where: { $0.id == "health-signals" && $0.level == .warning }))
    }

    func testActiveSnapshotSaysNoIssueObservedInsteadOfClaimingHealth() {
        let snapshot = makeSnapshot()

        XCTAssertTrue(snapshot.issues().isEmpty)
        XCTAssertFalse(snapshot.report().lowercased().contains("healthy"))
    }

    func testUnconfirmedHLSAndMacOS14FallbackStayObservational() {
        let waiting = makeSnapshot(
            playback: makePlayback(isLikelyHLS: nil)
        )
        XCTAssertEqual(
            waiting.issues().first(where: { $0.id == "waiting-hls-evidence" })?.level,
            .observation
        )

        let fallback = makeSnapshot(
            availability: .activeErrorLogFallback,
            playback: makePlayback(isLikelyHLS: true),
            monitor: .initial(for: .fallbackObserving)
        )
        XCTAssertEqual(
            fallback.issues().first(where: { $0.id == "reduced-attribution" })?.level,
            .notice
        )
    }

    func testRawDeliveryAndAccessLogEvidenceDoesNotBecomeCriticalContentDiagnosis() {
        let snapshot = makeSnapshot(
            network: makeNetwork(
                droppedVideoFrameCount: 20,
                overdueDownloadCount: 1,
                observedBitRate: 1,
                indicatedBitRate: 100
            ),
            errors: [
                PlaybackDiagnosticsError(
                    occurredAt: Date(timeIntervalSince1970: 100),
                    domain: NSURLErrorDomain,
                    code: URLError.timedOut.rawValue
                )
            ],
            events: [healthEvent(confidence: .high, mediaType: .audio)]
        )

        XCTAssertEqual(snapshot.issues().first(where: { $0.id == "health-signals" })?.level, .warning)
        XCTAssertEqual(snapshot.issues().first(where: { $0.id == "error-log" })?.level, .notice)
        XCTAssertEqual(snapshot.issues().first(where: { $0.id == "overdue-downloads" })?.level, .notice)
        XCTAssertEqual(snapshot.issues().first(where: { $0.id == "dropped-frames" })?.level, .notice)
        XCTAssertNil(snapshot.issues().first(where: { $0.id == "throughput-shortfall" }))
    }

    func testMuteTrackIdentityAndMonitorTelemetryAreIncludedInSafeReport() {
        var monitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        monitor.playlistRequestCount = 2
        monitor.segmentRequestCount = 8
        monitor.healthyPlaylistRequestCount = 1
        monitor.healthySegmentRequestCount = 7
        monitor.latestFailureContext = PlaybackHealthRequestFailureContext(
            signalKind: .mediaSegmentRequestFailure,
            mediaType: .audio,
            occurredAt: Date(timeIntervalSince1970: 100),
            requestDuration: 0.4,
            timeToFirstByte: 0.1,
            responseDuration: 0.3,
            wasReadFromCache: false,
            segmentDuration: 6,
            byteCount: 1_024
        )
        let snapshot = makeSnapshot(
            playback: makePlayback(isMuted: true, volume: 0),
            monitor: monitor
        )

        let report = snapshot.report()

        XCTAssertEqual(snapshot.issues().first(where: { $0.id == "player-muted" })?.level, .warning)
        XCTAssertTrue(report.contains("muted=true"))
        XCTAssertTrue(report.contains("selected_audio_track_id=sha256:0123456789abcdef"))
        XCTAssertTrue(report.contains("hls_playlist_requests=2"))
        XCTAssertTrue(report.contains("hls_segment_requests=8"))
        XCTAssertTrue(report.contains("request_seconds=0.400"))
        XCTAssertFalse(report.contains("https://"))
        XCTAssertFalse(report.contains("server_address="))
    }

    func testAvailabilityPreservesActualCoverageState() {
        XCTAssertEqual(
            PlayerManager.shared.fetchPlaybackDiagnostics().session.availability,
            .noPlayerItem
        )
        XCTAssertEqual(
            PlaybackDiagnosticsSnapshot.unavailable(.noPlayerItem).session.availability,
            .noPlayerItem
        )
        XCTAssertEqual(
            PlaybackDiagnosticsSnapshot.unavailable(.unsupportedBackend).session.availability,
            .unsupportedBackend
        )
    }

    func testStopThenPlayStartsFreshDiagnosticsForTheRetainedItem() {
        let manager = PlayerManager.shared
        manager.load(playerItem: PlayerItem(
            title: "Diagnostics replay",
            url: URL(string: "https://example.com/replay.m3u8")!,
            playbackHealthAssetIdentifier: "diagnostics-replay"
        ))

        let sessionID = manager.fetchPlaybackDiagnostics().session.sessionID
        XCTAssertNotNil(sessionID)
        XCTAssertTrue(manager.hasActivePlaybackDiagnosticsItem)

        manager.stop()
        XCTAssertFalse(manager.hasActivePlaybackDiagnosticsItem)

        manager.play()
        let resumed = manager.fetchPlaybackDiagnostics()
        XCTAssertTrue(manager.hasActivePlaybackDiagnosticsItem)
        XCTAssertNotEqual(resumed.session.sessionID, sessionID)
        XCTAssertNil(resumed.storyboard.endedAt)
    }

    func testBufferStateRejectsInvalidTimeAndRangesWithoutInventingHeadroom() {
        let validRange = CMTimeRange(
            start: CMTime(seconds: 10, preferredTimescale: 600),
            duration: CMTime(seconds: 5, preferredTimescale: 600)
        )

        XCTAssertEqual(
            playbackDiagnosticsBufferState(
                currentTime: nil,
                loadedTimeRanges: [validRange]
            ),
            .unknown
        )
        XCTAssertEqual(
            playbackDiagnosticsBufferState(
                currentTime: .nan,
                loadedTimeRanges: [validRange]
            ),
            .unknown
        )
        XCTAssertEqual(
            playbackDiagnosticsBufferState(
                currentTime: 10,
                loadedTimeRanges: [
                    CMTimeRange(
                        start: .invalid,
                        duration: CMTime(seconds: 5, preferredTimescale: 600)
                    ),
                    CMTimeRange(
                        start: .zero,
                        duration: CMTime(seconds: -1, preferredTimescale: 600)
                    ),
                ]
            ),
            .unknown
        )
    }

    func testBufferStateMergesOnlyAdjacentRangesAroundCurrentPosition() {
        let state = playbackDiagnosticsBufferState(
            currentTime: 11,
            loadedTimeRanges: [
                CMTimeRange(
                    start: CMTime(seconds: 10, preferredTimescale: 600),
                    duration: CMTime(seconds: 2, preferredTimescale: 600)
                ),
                CMTimeRange(
                    start: CMTime(seconds: 12.1, preferredTimescale: 600),
                    duration: CMTime(seconds: 2.9, preferredTimescale: 600)
                ),
                CMTimeRange(
                    start: CMTime(seconds: 20, preferredTimescale: 600),
                    duration: CMTime(seconds: 5, preferredTimescale: 600)
                ),
            ]
        )

        XCTAssertEqual(state.bufferedUntil ?? -1, 15, accuracy: 0.001)
        XCTAssertEqual(state.headroom ?? -1, 4, accuracy: 0.001)
    }

    func testPlaybackMetadataSanitizersRejectNonfiniteAndExtremeValues() {
        XCTAssertEqual(
            sanitizedPlaybackDiagnosticsResolution(width: 1920, height: 1080),
            "1920×1080"
        )
        XCTAssertNil(
            sanitizedPlaybackDiagnosticsResolution(width: .infinity, height: 1080)
        )
        XCTAssertNil(
            sanitizedPlaybackDiagnosticsResolution(width: 100_000, height: 1080)
        )
        XCTAssertEqual(sanitizedPlaybackDiagnosticsFrameRate(59.94), 59.94)
        XCTAssertNil(sanitizedPlaybackDiagnosticsFrameRate(.infinity))
        XCTAssertNil(sanitizedPlaybackDiagnosticsFrameRate(2_000))
        XCTAssertEqual(sanitizedPlaybackDiagnosticsRate(-2), -2)
        XCTAssertNil(sanitizedPlaybackDiagnosticsRate(.nan))
        XCTAssertNil(sanitizedPlaybackDiagnosticsRate(100))
    }

    func testAccessLogAggregationSumsPeriodsAndKeepsLatestPointMetrics() {
        let first = makeNetwork(
            mediaRequestCount: 2,
            numberOfStalls: 1,
            droppedVideoFrameCount: 3,
            overdueDownloadCount: 4,
            bytesTransferred: 100,
            transferDuration: 5,
            observedBitRate: 9,
            indicatedBitRate: 10,
            segmentsDownloadedDuration: 6,
            durationWatched: 7,
            startupTime: 11,
            serverAddressChangeCount: 8
        )
        let latest = makeNetwork(
            mediaRequestCount: 20,
            numberOfStalls: 10,
            droppedVideoFrameCount: 30,
            overdueDownloadCount: 40,
            bytesTransferred: 1_000,
            transferDuration: 50,
            observedBitRate: 90,
            indicatedBitRate: 100,
            segmentsDownloadedDuration: 60,
            durationWatched: 70,
            startupTime: 110,
            serverAddressChangeCount: 80
        )

        let aggregate = PlaybackDiagnosticsSnapshot.Network.aggregatingAccessLogPeriods([first, latest])

        XCTAssertEqual(aggregate.accessLogEventCount, 2)
        XCTAssertEqual(aggregate.mediaRequestCount, 22)
        XCTAssertEqual(aggregate.numberOfStalls, 11)
        XCTAssertEqual(aggregate.droppedVideoFrameCount, 33)
        XCTAssertEqual(aggregate.overdueDownloadCount, 44)
        XCTAssertEqual(aggregate.bytesTransferred, 1_100)
        XCTAssertEqual(aggregate.transferDuration, 55)
        XCTAssertEqual(aggregate.segmentsDownloadedDuration, 66)
        XCTAssertEqual(aggregate.durationWatched, 77)
        XCTAssertEqual(aggregate.serverAddressChangeCount, 88)
        XCTAssertEqual(aggregate.observedBitRate, 90)
        XCTAssertEqual(aggregate.indicatedBitRate, 100)
        XCTAssertEqual(aggregate.startupTime, 110)
    }

    func testBufferAndAudioSelectionWarningsRequireReadyActivePlayback() {
        let noSelection = [
            PlaybackDiagnosticsTrack(
                identifier: "sha256:test",
                name: "Russian",
                languageCode: "ru",
                isSelected: false
            )
        ]
        let paused = makeSnapshot(
            playback: makePlayback(
                itemStatus: "ready",
                timeControlStatus: "paused",
                isPlaybackBufferEmpty: true
            ),
            audioTracks: noSelection
        )

        XCTAssertFalse(paused.issues().contains(where: { $0.id == "buffer-empty" }))
        XCTAssertFalse(paused.issues().contains(where: { $0.id == "missing-audio-selection" }))

        let active = makeSnapshot(
            playback: makePlayback(
                itemStatus: "ready",
                timeControlStatus: "playing",
                isPlaybackBufferEmpty: true
            ),
            audioTracks: noSelection
        )

        XCTAssertEqual(active.issues().first(where: { $0.id == "buffer-empty" })?.level, .warning)
        XCTAssertEqual(active.issues().first(where: { $0.id == "missing-audio-selection" })?.level, .warning)
    }

    func testCopiedReportContainsStructuredSafeStateOnly() {
        let manifestControlledName = "https://media.example/audio?token=manifest-secret"
        let evidenceID = UUID()
        let selectedTrack = PlaybackDiagnosticsTrack(
            identifier: "sha256:track",
            name: manifestControlledName,
            languageCode: "ru",
            isSelected: true
        )
        let snapshot = makeSnapshot(
            audioTracks: [selectedTrack],
            subtitleTracks: [
                PlaybackDiagnosticsTrack(
                    identifier: "sha256:subtitle",
                    name: manifestControlledName,
                    languageCode: "uz",
                    isSelected: false
                )
            ],
            errors: [
                PlaybackDiagnosticsError(
                    occurredAt: Date(timeIntervalSince1970: 100),
                    domain: NSURLErrorDomain,
                    code: URLError.timedOut.rawValue
                )
            ],
            events: [
                healthEvent(
                    confidence: .medium,
                    mediaType: .muxed,
                    selectedAudioTrack: PlaybackHealthAudioTrack(
                        identifier: "sha256:event-track",
                        languageCode: "ru",
                        displayName: manifestControlledName,
                        isSelected: true
                    )
                )
            ],
            storyboard: PlaybackDiagnosticsStoryboard(
                samples: [],
                evidence: [
                    PlaybackDiagnosticsEvidence(
                        id: evidenceID,
                        occurredAt: Date(timeIntervalSince1970: 101),
                        mediaTime: 10,
                        kind: .failedSegmentRequest,
                        level: .warning,
                        title: "Media segment request failed",
                        measurement: "HTTP 503"
                    )
                ],
                incidents: [
                    PlaybackDiagnosticsAutomaticIncident(
                        id: UUID(),
                        kind: .repeatedRequestFailures,
                        severity: .warning,
                        startedAt: Date(timeIntervalSince1970: 101),
                        lastObservedAt: Date(timeIntervalSince1970: 102),
                        endedAt: nil,
                        impact: "Multiple media requests failed.",
                        likelyCause: "Repeated delivery failures were measured.",
                        evidenceIDs: [evidenceID],
                        measuredValues: ["3 failures in 30 seconds"],
                        nextAction: "Inspect sanitized request timing.",
                        evidenceStrength: .direct
                    )
                ],
                bookmarks: [
                    PlaybackDiagnosticsBookmark(
                        id: UUID(),
                        capturedAt: Date(timeIntervalSince1970: 103),
                        mediaTime: 10,
                        selectedAudioTrack: selectedTrack,
                        itemStatus: "ready",
                        timeControlStatus: "playing",
                        waitingReason: nil,
                        bufferHeadroom: 20,
                        resolution: "1920×1080",
                        frameRate: 24,
                        observedBitRate: 5_000_000,
                        indicatedBitRate: 4_000_000,
                        accessLogStallCount: 1,
                        metricStallCount: 1,
                        errorLogEventCount: 3
                    )
                ]
            )
        )

        let report = snapshot.report()

        XCTAssertTrue(report.contains("availability=activeAVMetrics"))
        XCTAssertTrue(report.contains("signal=mediaSegmentRequestFailure"))
        XCTAssertFalse(report.contains("https://"))
        XCTAssertFalse(report.contains("token="))
        XCTAssertFalse(report.contains("authorization"))
        XCTAssertFalse(report.contains("server_address="))
        XCTAssertFalse(report.contains("error_comment="))
        XCTAssertFalse(report.contains(manifestControlledName))
        XCTAssertFalse(report.contains("track_name="))
        XCTAssertFalse(report.contains("name=\(manifestControlledName)"))
        XCTAssertTrue(report.contains("audio_track[0]=id=sha256:track language=ru"))
        XCTAssertTrue(report.contains("subtitle_track[0]=id=sha256:subtitle language=uz"))
        XCTAssertTrue(report.contains("track_id=sha256:event-track track_language=ru"))
        XCTAssertTrue(report.contains("kind=failedSegmentRequest"))
        XCTAssertTrue(report.contains("kind=repeatedRequestFailures"))
        XCTAssertTrue(report.contains("bookmarks=1"))
        XCTAssertTrue(report.contains("track_id=sha256:track track_language=ru"))
    }

    func testUnexpectedHTMLOrJSONMediaResponseIsAnObservationalIssue() {
        var monitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        for mime in [PlaybackHealthMIMECategory.html, .json, .binary] {
            monitor.requestTrace.record(
                PlaybackHealthRequestTraceEntry(
                    kind: .segment,
                    mediaType: .video,
                    occurredAt: Date(timeIntervalSince1970: 1),
                    didFail: false,
                    didRecover: nil,
                    requestDuration: 0.2,
                    timeToFirstByte: 0.1,
                    transferDuration: 0.1,
                    httpStatusCode: 200,
                    mimeCategory: mime,
                    wasReadFromCache: false,
                    redirectCount: 0,
                    networkProtocol: "h2",
                    responseBodyBytes: 256,
                    decodedBodyBytes: 256,
                    reusedConnection: true,
                    proxyConnection: false,
                    constrainedNetwork: false,
                    expensiveNetwork: false,
                    cellularNetwork: false,
                    multipathConnection: false,
                    fetchType: .networkLoad,
                    segmentDeliveryRatio: 0.1
                )
            )
        }

        let issue = makeSnapshot(monitor: monitor).issues().first {
            $0.id == "unexpected-hls-response-type"
        }

        XCTAssertEqual(issue?.level, .notice)
        XCTAssertEqual(issue?.scope, .historical)
        XCTAssertTrue(issue?.detail.contains("2 retained") == true)
    }

    func testPlayerManagerBoundsHistoryWithoutReplacingReporterSink() throws {
        let manager = PlayerManager.shared
        manager.isPlaybackHealthMonitoringEnabled = true
        manager.setPlayer(type: .avPlayer)
        manager.load(
            playerItem: PlayerItem(
                title: "Diagnostics",
                url: URL(string: "https://example.invalid/playerkit-history.m3u8")!,
                playbackHealthAssetIdentifier: "42",
                playbackHealthMonitoringEligible: true
            )
        )
        var forwardedCount = 0
        manager.onPlaybackHealthEvent = { _ in
            forwardedCount += 1
        }

        let wrapper = try XCTUnwrap(manager.currentPlayer as? AVPlayerWrapper)
        let sessionID = try XCTUnwrap(wrapper.activePlaybackHealthSessionID)
        for index in 0..<55 {
            wrapper.onPlaybackHealthEvent?(
                healthEvent(
                    sessionID: sessionID,
                    mediaTime: Double(index),
                    confidence: .low,
                    mediaType: .unknown
                )
            )
        }

        XCTAssertEqual(forwardedCount, 55)
        XCTAssertEqual(manager.recentPlaybackHealthEvents.count, 50)
        XCTAssertEqual(manager.recentPlaybackHealthEvents.first?.mediaTime, 5)
        XCTAssertEqual(manager.recentPlaybackHealthEvents.last?.mediaTime, 54)
        XCTAssertEqual(manager.fetchPlaybackDiagnostics().history.receivedCount, 55)
        XCTAssertEqual(manager.fetchPlaybackDiagnostics().history.retainedCount, 50)
        XCTAssertEqual(manager.fetchPlaybackDiagnostics().history.droppedCount, 5)

        manager.clearPlaybackDiagnosticsEvents()

        XCTAssertEqual(manager.fetchPlaybackDiagnostics().history.receivedCount, 55)
        XCTAssertEqual(manager.fetchPlaybackDiagnostics().history.retainedCount, 0)
        XCTAssertEqual(manager.fetchPlaybackDiagnostics().history.droppedCount, 5)
        XCTAssertEqual(manager.fetchPlaybackDiagnostics().history.clearedCount, 50)
    }

    func testWrapperSnapshotReportsNumericAssetIDAndFingerprintsOpaqueIdentifier() {
        let wrapper = AVPlayerWrapper()
        defer { wrapper.stop() }
        let remoteHLSURL = URL(string: "https://example.invalid/playerkit-current.m3u8")!
        wrapper.load(
            url: remoteHLSURL,
            playbackHealthAssetIdentifier: "42",
            playbackHealthMonitoringEnabled: true,
            playbackHealthMonitoringEligible: true
        )

        let attached = wrapper.fetchPlaybackDiagnostics(
            monitoringEnabled: true,
            recentHealthEvents: []
        )

        XCTAssertTrue(attached.session.monitorAttached)
        XCTAssertEqual(attached.session.assetIdentifier, "42")
        XCTAssertEqual(attached.session.sessionID, wrapper.activePlaybackHealthSessionID)
        XCTAssertNotNil(attached.session.startedAt)
        XCTAssertEqual(attached.playback.isLikelyHLS, true)
        if #available(macOS 26, *) {
            XCTAssertTrue(
                attached.session.availability == .startingAVMetrics
                    || attached.session.availability == .activeAVMetrics
            )
        } else {
            XCTAssertEqual(attached.session.availability, .activeErrorLogFallback)
        }

        let stillAttached = wrapper.fetchPlaybackDiagnostics(
            monitoringEnabled: false,
            recentHealthEvents: []
        )
        XCTAssertTrue(stillAttached.session.monitorAttached)
        XCTAssertEqual(stillAttached.session.availability, attached.session.availability)

        let opaqueIdentifier = "eyJhbGciOiJIUzI1NiJ9.eyJmaWxlX2lkIjo0Mn0.signature"
        wrapper.load(
            url: remoteHLSURL,
            playbackHealthAssetIdentifier: opaqueIdentifier,
            playbackHealthMonitoringEnabled: true,
            playbackHealthMonitoringEligible: true
        )

        let opaqueSnapshot = wrapper.fetchPlaybackDiagnostics(
            monitoringEnabled: true,
            recentHealthEvents: []
        )
        let fingerprint = opaqueSnapshot.session.assetIdentifier
        XCTAssertTrue(fingerprint?.hasPrefix("sha256:") == true)
        XCTAssertEqual(fingerprint?.count, 71)
        XCTAssertNotEqual(fingerprint, opaqueIdentifier)
        XCTAssertFalse(opaqueSnapshot.report().contains(opaqueIdentifier))
    }

    func testWrapperCreatesPrivatePerItemIdentityWithoutAVMetrics() throws {
        let wrapper = AVPlayerWrapper()
        defer { wrapper.stop() }
        let firstURL = try XCTUnwrap(
            URL(
                string: "https://media.example/movie/master.m3u8?token=first#one"
            )
        )
        let secondURL = try XCTUnwrap(
            URL(
                string: "https://media.example/movie/master.m3u8?token=second#two"
            )
        )

        wrapper.load(url: firstURL)
        let first = wrapper.fetchPlaybackDiagnostics(
            monitoringEnabled: false,
            recentHealthEvents: []
        )
        wrapper.load(url: secondURL)
        let second = wrapper.fetchPlaybackDiagnostics(
            monitoringEnabled: false,
            recentHealthEvents: []
        )

        XCTAssertFalse(first.session.monitorAttached)
        XCTAssertNotNil(first.session.sessionID)
        XCTAssertNotNil(first.session.startedAt)
        XCTAssertTrue(first.session.assetIdentifier?.hasPrefix("sha256:") == true)
        XCTAssertEqual(first.session.assetIdentifier, second.session.assetIdentifier)
        XCTAssertNotEqual(first.session.sessionID, second.session.sessionID)
        XCTAssertFalse(first.report().contains("token=first"))
        XCTAssertFalse(second.report().contains("token=second"))
    }

    func testTerminalFailureVariantWaitAndTransportEvidenceAreSanitizedAndScoped() {
        var monitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        monitor.terminalFailure = PlaybackHealthTerminalFailure(
            occurredAt: Date(timeIntervalSince1970: 101),
            mediaTime: 44,
            error: PlaybackDiagnosticsError(
                occurredAt: Date(timeIntervalSince1970: 101),
                domain: NSURLErrorDomain,
                code: URLError.networkConnectionLost.rawValue
            )
        )
        monitor.variantSwitches.totalCount = 3
        monitor.variantSwitches.succeededCount = 2
        monitor.variantSwitches.failedCount = 1
        monitor.variantSwitches.upCount = 1
        monitor.variantSwitches.downCount = 1
        monitor.variantSwitches.lateralCount = 1
        monitor.waiting.initialWaitCount = 1
        monitor.waiting.postStartWaitCount = 2
        monitor.waiting.totalWaitDuration = 8
        monitor.waiting.longestWaitDuration = 5
        monitor.slowDelivery.audioCount = 2
        monitor.slowDelivery.worstAudioRatio = 1.75
        monitor.latestFailureContext = PlaybackHealthRequestFailureContext(
            signalKind: .mediaSegmentRequestFailure,
            mediaType: .audio,
            occurredAt: Date(timeIntervalSince1970: 100),
            requestDuration: 2,
            timeToFirstByte: 0.5,
            responseDuration: 1.5,
            wasReadFromCache: false,
            segmentDuration: 1,
            requestedByteRangeLength: 1_024,
            responseBodyBytes: 768,
            httpStatusCode: 503,
            redirectCount: 1,
            networkProtocol: "h2",
            dnsDuration: 0.02,
            connectDuration: 0.05,
            tlsDuration: 0.03
        )

        let snapshot = makeSnapshot(monitor: monitor)
        let terminalIssue = snapshot.issues().first {
            $0.id == "terminal-playback-failure"
        }
        let report = snapshot.report()

        XCTAssertEqual(terminalIssue?.scope, .active)
        XCTAssertNotNil(terminalIssue?.recommendation)
        XCTAssertEqual(
            snapshot.issues().first(where: { $0.id == "variant-switch-failures" })?.scope,
            .historical
        )
        XCTAssertEqual(
            snapshot.issues().first(where: { $0.id == "slow-segment-delivery" })?.scope,
            .historical
        )
        XCTAssertTrue(report.contains("terminal_failure="))
        XCTAssertTrue(report.contains("variant_switch_failed=1"))
        XCTAssertTrue(report.contains("post_start_wait_count=2"))
        XCTAssertTrue(report.contains("http_status=503"))
        XCTAssertTrue(report.contains("requested_byte_range_length=1024"))
        XCTAssertTrue(report.contains("response_body_bytes=768"))
        XCTAssertTrue(report.contains("protocol=h2"))
        XCTAssertTrue(report.contains("os_version="))
        XCTAssertFalse(report.contains("https://"))
        XCTAssertFalse(report.contains("authorization"))
    }

    func testNaturalEndOnlySuppressesCoverageAndFinalBufferSuppressesLowBuffer() {
        var monitor = PlaybackHealthMonitorTelemetry.initial(for: .fallbackObserving)
        monitor.fallbackReason = .metricsEnded
        monitor.naturalEnd = PlaybackHealthNaturalEndEvidence(
            occurredAt: Date(timeIntervalSince1970: 120),
            mediaTime: 120
        )
        monitor.waiting.postStartWaitCount = 1
        monitor.waiting.currentKind = .postStart
        monitor.waiting.currentWaitDuration = 2
        let waitingSnapshot = makeSnapshot(
            availability: .activeErrorLogFallback,
            playback: makePlayback(
                timeControlStatus: "waiting",
                isPlaybackBufferEmpty: true,
                currentTime: 118,
                duration: 120,
                isPlaybackLikelyToKeepUp: false
            ),
            network: makeNetwork(
                observedBitRate: 1,
                indicatedBitRate: 100
            ),
            monitor: monitor
        )

        let waitingIDs = Set(waitingSnapshot.issues().map(\.id))

        XCTAssertFalse(waitingIDs.contains("reduced-attribution"))
        XCTAssertTrue(waitingIDs.contains("waiting"))
        XCTAssertTrue(waitingIDs.contains("buffer-empty"))

        var noNaturalEndMonitor = monitor
        noNaturalEndMonitor.naturalEnd = nil
        XCTAssertTrue(
            makeSnapshot(
                availability: .activeErrorLogFallback,
                monitor: noNaturalEndMonitor
            ).issues().contains(where: { $0.id == "reduced-attribution" })
        )

        let playingSnapshot = makeSnapshot(
            playback: makePlayback(
                timeControlStatus: "playing",
                currentTime: 118,
                duration: 120,
                isPlaybackLikelyToKeepUp: false,
                bufferedUntil: 119.74,
                bufferHeadroom: 1.74
            ),
            network: makeNetwork(observedBitRate: 1, indicatedBitRate: 100),
            monitor: monitor
        )
        let playingIDs = Set(playingSnapshot.issues().map(\.id))
        XCTAssertTrue(playingIDs.contains("low-buffer"))
        XCTAssertTrue(playingIDs.contains("not-likely-to-keep-up"))
        XCTAssertTrue(playingIDs.contains("throughput-shortfall"))

        let fullyBufferedFinalRange = makeSnapshot(
            playback: makePlayback(
                timeControlStatus: "playing",
                currentTime: 118,
                duration: 120,
                bufferedUntil: 119.75,
                bufferHeadroom: 1.75
            )
        )
        XCTAssertFalse(
            fullyBufferedFinalRange.issues().contains(where: { $0.id == "low-buffer" })
        )
    }

    func testWaitingWarnsOnlyWithIndependentDeliveryPressureAndInitialWaitStaysObservational() {
        var initialWait = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        initialWait.waiting.initialWaitCount = 1
        initialWait.waiting.currentWaitDuration = 5
        let startup = makeSnapshot(
            playback: makePlayback(
                timeControlStatus: "waiting",
                isPlaybackBufferEmpty: true
            ),
            monitor: initialWait
        )

        XCTAssertEqual(
            startup.issues().first(where: { $0.id == "waiting" })?.level,
            .observation
        )
        XCTAssertEqual(
            startup.issues().first(where: { $0.id == "waiting" })?.scope,
            .active
        )
        XCTAssertNil(startup.issues().first(where: { $0.id == "buffer-empty" }))

        var shortRebuffer = initialWait
        shortRebuffer.waiting.initialWaitCount = 0
        shortRebuffer.waiting.postStartWaitCount = 1
        shortRebuffer.waiting.currentKind = .postStart
        shortRebuffer.waiting.currentWaitDuration = 0.999
        let short = makeSnapshot(
            playback: makePlayback(
                timeControlStatus: "waiting",
                isPlaybackBufferEmpty: true
            ),
            monitor: shortRebuffer
        )
        XCTAssertEqual(
            short.issues().first(where: { $0.id == "waiting" })?.level,
            .observation
        )
        XCTAssertNil(short.issues().first(where: { $0.id == "buffer-empty" }))

        var establishedRebuffer = shortRebuffer
        establishedRebuffer.waiting.currentWaitDuration = 1
        let established = makeSnapshot(
            playback: makePlayback(
                timeControlStatus: "waiting",
                isPlaybackBufferEmpty: true
            ),
            monitor: establishedRebuffer
        )
        XCTAssertEqual(
            established.issues().first(where: { $0.id == "waiting" })?.level,
            .warning
        )
        XCTAssertEqual(
            established.issues().first(where: { $0.id == "buffer-empty" })?.level,
            .warning
        )
    }

    func testVariantDirectionCountsOnlySuccessfulLikeForLikeSwitches() {
        var switches = PlaybackHealthVariantSwitchTelemetry()
        let averageOnly = PlaybackHealthVariant(
            peakBitRate: nil,
            averageBitRate: 1_000,
            resolution: nil,
            frameRate: nil
        )
        let peakOnly = PlaybackHealthVariant(
            peakBitRate: 2_000,
            averageBitRate: nil,
            resolution: nil,
            frameRate: nil
        )
        switches.record(
            from: averageOnly,
            to: peakOnly,
            succeeded: true,
            occurredAt: Date(timeIntervalSince1970: 1)
        )
        switches.record(
            from: averageOnly,
            to: PlaybackHealthVariant(
                peakBitRate: nil,
                averageBitRate: 2_000,
                resolution: nil,
                frameRate: nil
            ),
            succeeded: false,
            occurredAt: Date(timeIntervalSince1970: 2)
        )
        switches.record(
            from: PlaybackHealthVariant(
                peakBitRate: 9_000,
                averageBitRate: 1_000,
                resolution: nil,
                frameRate: nil
            ),
            to: PlaybackHealthVariant(
                peakBitRate: 1_000,
                averageBitRate: 2_000,
                resolution: nil,
                frameRate: nil
            ),
            succeeded: true,
            occurredAt: Date(timeIntervalSince1970: 3)
        )

        XCTAssertEqual(switches.totalCount, 3)
        XCTAssertEqual(switches.succeededCount, 2)
        XCTAssertEqual(switches.failedCount, 1)
        XCTAssertEqual(switches.upCount, 1)
        XCTAssertEqual(switches.downCount, 0)
        XCTAssertEqual(switches.lateralCount, 0)
        XCTAssertEqual(switches.unknownDirectionCount, 1)
        XCTAssertEqual(
            switches.upCount
                + switches.downCount
                + switches.lateralCount
                + switches.unknownDirectionCount,
            switches.succeededCount
        )
        XCTAssertEqual(switches.recentTransitions.count, 3)
        XCTAssertEqual(
            switches.recentTransitions.last?.occurredAt,
            Date(timeIntervalSince1970: 3)
        )
    }

    func testRecentVariantTransitionsAreBounded() {
        var switches = PlaybackHealthVariantSwitchTelemetry()
        let variant = PlaybackHealthVariant(
            peakBitRate: 2_000,
            averageBitRate: 1_000,
            resolution: "1920×1080",
            frameRate: 24
        )

        for index in 0..<(PlaybackHealthVariantSwitchTelemetry.recentTransitionCapacity + 5) {
            switches.record(
                from: variant,
                to: variant,
                succeeded: true,
                occurredAt: Date(timeIntervalSince1970: Double(index))
            )
        }

        XCTAssertEqual(
            switches.recentTransitions.count,
            PlaybackHealthVariantSwitchTelemetry.recentTransitionCapacity
        )
        XCTAssertEqual(
            switches.recentTransitions.first?.occurredAt,
            Date(timeIntervalSince1970: 5)
        )
    }

    func testPlaybackSummarySanitizesInvalidValuesAndUnsafeErrorDomain() {
        let summary = PlaybackHealthPlaybackSummaryTelemetry(
            occurredAt: Date(timeIntervalSince1970: 100.125),
            errorDomain: "https://keys.example/key?token=secret",
            errorCode: 403,
            errorDidRecover: false,
            recoverableErrorCount: -1,
            stallCount: 2,
            variantSwitchCount: -3,
            playbackDuration: 30,
            mediaResourceRequestCount: 20,
            timeSpentRecoveringFromStall: .nan,
            timeSpentInInitialStartup: 1.25,
            timeWeightedAverageBitrate: -1,
            timeWeightedPeakBitrate: 4_000_000
        )

        XCTAssertNil(summary.error?.domain)
        XCTAssertEqual(summary.error?.code, 403)
        XCTAssertEqual(summary.errorDidRecover, false)
        XCTAssertNil(summary.recoverableErrorCount)
        XCTAssertEqual(summary.stallCount, 2)
        XCTAssertNil(summary.variantSwitchCount)
        XCTAssertEqual(summary.playbackDuration, 30)
        XCTAssertNil(summary.timeSpentRecoveringFromStall)
        XCTAssertEqual(summary.timeSpentInInitialStartup, 1.25)
        XCTAssertNil(summary.timeWeightedAverageBitrate)
        XCTAssertEqual(summary.timeWeightedPeakBitrate, 4_000_000)
    }

    func testRequestTraceIsBoundedAndReportCannotContainRequestIdentifiers() {
        var monitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        monitor.contentKeys.record(
            mediaType: .audio,
            failed: false,
            clientInitiated: true
        )
        monitor.contentKeys.record(
            mediaType: .video,
            failed: true,
            clientInitiated: false
        )
        for index in 0..<55 {
            monitor.requestTrace.record(requestTraceEntry(index: index))
        }
        let snapshot = makeSnapshot(monitor: monitor)
        let report = snapshot.report()

        XCTAssertEqual(monitor.requestTrace.receivedCount, 55)
        XCTAssertEqual(monitor.requestTrace.entries.count, 50)
        XCTAssertEqual(monitor.requestTrace.droppedCount, 5)
        XCTAssertEqual(
            monitor.requestTrace.entries.first?.occurredAt,
            Date(timeIntervalSince1970: 5.125)
        )
        XCTAssertTrue(report.contains("content_key_requests=2"))
        XCTAssertTrue(report.contains("content_key_requests_failed=1"))
        XCTAssertTrue(report.contains("request_trace_received=55"))
        XCTAssertTrue(report.contains("request_trace_dropped=5"))
        XCTAssertTrue(report.contains("kind=contentKey"))
        XCTAssertFalse(report.contains("https://"))
        XCTAssertFalse(report.contains("token="))
        XCTAssertFalse(report.contains("server_address="))
        XCTAssertFalse(report.contains("content_key_specifier"))
        XCTAssertFalse(report.contains("avmetric_session_id="))
    }

    func testReportTimestampsIncludeFractionalSeconds() {
        let snapshot = makeSnapshot(
            capturedAt: Date(timeIntervalSince1970: 200.123)
        )

        XCTAssertTrue(
            snapshot.report().contains(
                "captured_at=1970-01-01T00:03:20.123Z"
            )
        )
    }

    func testReportUsesUnknownForUnavailableMeasurements() {
        let report = PlaybackDiagnosticsSnapshot
            .unavailable(.noPlayerItem)
            .report()

        XCTAssertTrue(report.contains("loaded_range_count=unknown"))
        XCTAssertTrue(report.contains("likely_to_keep_up=unknown"))
        XCTAssertTrue(report.contains("access_log_periods=unknown"))
        XCTAssertTrue(report.contains("error_log_entries=unknown"))
        XCTAssertTrue(report.contains("storyboard_samples=unknown"))
        XCTAssertFalse(report.contains("loaded_range_count=0"))
    }

    func testReportRedactsUntrustedFreeFormText() {
        let canary = "https://user@example.com/segment?token=report-secret"
        let snapshot = makeSnapshot(
            errors: [
                PlaybackDiagnosticsError(
                    occurredAt: Date(timeIntervalSince1970: 100),
                    domain: canary,
                    code: 500
                )
            ],
            storyboard: PlaybackDiagnosticsStoryboard(
                samples: [],
                evidence: [
                    PlaybackDiagnosticsEvidence(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                        occurredAt: Date(timeIntervalSince1970: 101),
                        mediaTime: 10,
                        kind: .errorLogEntry,
                        level: .notice,
                        title: canary,
                        measurement: "authorization=Bearer report-secret"
                    )
                ],
                incidents: [],
                bookmarks: []
            )
        )

        let report = snapshot.report()

        XCTAssertTrue(report.contains("[redacted]"))
        XCTAssertFalse(report.contains(canary))
        XCTAssertFalse(report.contains("report-secret"))
        XCTAssertFalse(report.contains("user@example.com"))
    }

    func testReportOrderingIsStableAcrossEquivalentCollectionOrder() {
        let sampleOne = reportSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            capturedAt: Date(timeIntervalSince1970: 110),
            mediaTime: 10
        )
        let sampleTwo = reportSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            capturedAt: Date(timeIntervalSince1970: 120),
            mediaTime: 20
        )
        let evidenceOne = PlaybackDiagnosticsEvidence(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            occurredAt: Date(timeIntervalSince1970: 111),
            mediaTime: 11,
            kind: .failedSegmentRequest,
            level: .warning,
            title: "Segment request failed",
            measurement: "HTTP 503"
        )
        let evidenceTwo = PlaybackDiagnosticsEvidence(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            occurredAt: Date(timeIntervalSince1970: 121),
            mediaTime: 21,
            kind: .recovery,
            level: .observation,
            title: "Playback recovered",
            measurement: "2.000 seconds"
        )
        let incidentID = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
        let incidentForward = reportIncident(
            id: incidentID,
            startedAt: Date(timeIntervalSince1970: 112),
            evidenceIDs: [evidenceOne.id, evidenceTwo.id],
            measuredValues: ["HTTP 503", "2.000 seconds"]
        )
        let incidentReverse = reportIncident(
            id: incidentID,
            startedAt: Date(timeIntervalSince1970: 112),
            evidenceIDs: [evidenceTwo.id, evidenceOne.id],
            measuredValues: ["2.000 seconds", "HTTP 503"]
        )
        let secondIncident = reportIncident(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
            startedAt: Date(timeIntervalSince1970: 122),
            evidenceIDs: [evidenceTwo.id],
            measuredValues: ["Recovered"]
        )
        let bookmarkID = UUID(uuidString: "00000000-0000-0000-0000-000000000031")!
        let bookmarkForward = reportBookmark(
            id: bookmarkID,
            capturedAt: Date(timeIntervalSince1970: 113),
            nearbySampleIDs: [sampleOne.id, sampleTwo.id],
            nearbyEvidenceIDs: [evidenceOne.id, evidenceTwo.id]
        )
        let bookmarkReverse = reportBookmark(
            id: bookmarkID,
            capturedAt: Date(timeIntervalSince1970: 113),
            nearbySampleIDs: [sampleTwo.id, sampleOne.id],
            nearbyEvidenceIDs: [evidenceTwo.id, evidenceOne.id]
        )
        let secondBookmark = reportBookmark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000032")!,
            capturedAt: Date(timeIntervalSince1970: 123),
            nearbySampleIDs: [sampleTwo.id],
            nearbyEvidenceIDs: [evidenceTwo.id]
        )
        let audioTracks = [
            PlaybackDiagnosticsTrack(
                identifier: "sha256:audio-a",
                name: "Audio A",
                languageCode: "en",
                isSelected: true
            ),
            PlaybackDiagnosticsTrack(
                identifier: "sha256:audio-b",
                name: "Audio B",
                languageCode: "uz",
                isSelected: false
            ),
        ]
        let subtitleTracks = [
            PlaybackDiagnosticsTrack(
                identifier: "sha256:subtitle-a",
                name: "Subtitle A",
                languageCode: "en",
                isSelected: false
            ),
            PlaybackDiagnosticsTrack(
                identifier: "sha256:subtitle-b",
                name: "Subtitle B",
                languageCode: "uz",
                isSelected: true
            ),
        ]
        let errors = [
            PlaybackDiagnosticsError(
                occurredAt: Date(timeIntervalSince1970: 114),
                domain: NSURLErrorDomain,
                code: -1
            ),
            PlaybackDiagnosticsError(
                occurredAt: Date(timeIntervalSince1970: 124),
                domain: NSPOSIXErrorDomain,
                code: 2
            ),
        ]
        let events = [
            healthEvent(
                mediaTime: 14,
                confidence: .medium,
                mediaType: .audio
            ),
            healthEvent(
                mediaTime: 24,
                confidence: .high,
                mediaType: .audio
            ),
        ]
        var forwardMonitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        forwardMonitor.requestTrace.record(requestTraceEntry(index: 1))
        forwardMonitor.requestTrace.record(requestTraceEntry(index: 2))
        var reverseMonitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        reverseMonitor.requestTrace.record(requestTraceEntry(index: 2))
        reverseMonitor.requestTrace.record(requestTraceEntry(index: 1))
        let forwardStoryboard = PlaybackDiagnosticsStoryboard(
            sessionStartedAt: Date(timeIntervalSince1970: 100),
            firstPlayingAt: Date(timeIntervalSince1970: 101),
            firstLikelyToKeepUpAt: Date(timeIntervalSince1970: 102),
            endedAt: Date(timeIntervalSince1970: 130),
            samples: [sampleOne, sampleTwo],
            evidence: [evidenceOne, evidenceTwo],
            incidents: [incidentForward, secondIncident],
            bookmarks: [bookmarkForward, secondBookmark]
        )
        let reverseStoryboard = PlaybackDiagnosticsStoryboard(
            sessionStartedAt: Date(timeIntervalSince1970: 100),
            firstPlayingAt: Date(timeIntervalSince1970: 101),
            firstLikelyToKeepUpAt: Date(timeIntervalSince1970: 102),
            endedAt: Date(timeIntervalSince1970: 130),
            samples: [sampleTwo, sampleOne],
            evidence: [evidenceTwo, evidenceOne],
            incidents: [secondIncident, incidentReverse],
            bookmarks: [secondBookmark, bookmarkReverse]
        )

        let forward = makeSnapshot(
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks,
            errors: errors,
            events: events,
            monitor: forwardMonitor,
            storyboard: forwardStoryboard
        )
        let reverse = makeSnapshot(
            audioTracks: Array(audioTracks.reversed()),
            subtitleTracks: Array(subtitleTracks.reversed()),
            errors: Array(errors.reversed()),
            events: Array(events.reversed()),
            monitor: reverseMonitor,
            storyboard: reverseStoryboard
        )

        XCTAssertEqual(forward.report(), reverse.report())
    }

    func testBookmarksAreBoundedClearedAndResetPerItem() throws {
        let manager = PlayerManager.shared
        manager.isPlaybackHealthMonitoringEnabled = true
        manager.setPlayer(type: .avPlayer)
        manager.load(
            playerItem: PlayerItem(
                title: "First",
                url: FileManager.default.temporaryDirectory
                    .appendingPathComponent("incident-first.m3u8"),
                playbackHealthAssetIdentifier: "42"
            )
        )

        for _ in 0..<22 {
            XCTAssertNotNil(manager.capturePlaybackDiagnosticsBookmark())
        }

        XCTAssertEqual(manager.fetchPlaybackDiagnostics().storyboard.bookmarks.count, 20)
        XCTAssertTrue(manager.fetchPlaybackDiagnostics().report().contains("bookmarks=20"))

        manager.clearPlaybackDiagnosticsEvents()
        XCTAssertTrue(manager.fetchPlaybackDiagnostics().storyboard.bookmarks.isEmpty)

        XCTAssertNotNil(manager.capturePlaybackDiagnosticsBookmark())
        manager.load(
            playerItem: PlayerItem(
                title: "Second",
                url: FileManager.default.temporaryDirectory
                    .appendingPathComponent("incident-second.m3u8"),
                playbackHealthAssetIdentifier: "43"
            )
        )
        XCTAssertTrue(manager.fetchPlaybackDiagnostics().storyboard.bookmarks.isEmpty)
    }

    func testStoppingFreezesSessionAndResetClearsIt() throws {
        let manager = PlayerManager.shared
        manager.setPlayer(type: .avPlayer)
        manager.load(
            playerItem: PlayerItem(
                title: "Lifecycle",
                url: FileManager.default.temporaryDirectory
                    .appendingPathComponent("diagnostics-lifecycle.m3u8"),
                playbackHealthAssetIdentifier: "44"
            )
        )

        let active = manager.fetchPlaybackDiagnostics()
        let sessionID = try XCTUnwrap(active.session.sessionID)
        XCTAssertTrue(manager.hasActivePlaybackDiagnosticsItem)
        XCTAssertFalse(active.storyboard.samples.isEmpty)

        manager.stop()

        let frozen = manager.fetchPlaybackDiagnostics()
        XCTAssertFalse(manager.hasActivePlaybackDiagnosticsItem)
        XCTAssertEqual(frozen.session.sessionID, sessionID)
        XCTAssertNotNil(frozen.storyboard.endedAt)
        XCTAssertNil(manager.capturePlaybackDiagnosticsBookmark())

        manager.resetPlayer()

        let reset = manager.fetchPlaybackDiagnostics()
        XCTAssertEqual(reset.session.availability, .noPlayerItem)
        XCTAssertTrue(reset.storyboard.samples.isEmpty)
    }

    func testRetainedBookmarkTrackDropsManifestControlledDisplayName() throws {
        let canary = "https://media.example/audio?token=retained-secret"
        let retained = try XCTUnwrap(
            retainedPlaybackDiagnosticsAudioTrack(
                PlaybackDiagnosticsTrack(
                    identifier: "sha256:0123456789abcdef",
                    name: canary,
                    languageCode: "uz",
                    isSelected: true
                )
            )
        )

        XCTAssertEqual(retained.identifier, "sha256:0123456789abcdef")
        XCTAssertEqual(retained.languageCode, "uz")
        XCTAssertEqual(retained.name, "Selected audio track")
        XCTAssertFalse(String(describing: retained).contains(canary))
    }

    @MainActor
    func testOptInRealHLSMetricsSmoke() async throws {
        // ponytail: Keep public-network playback out of the default unit suite;
        // set PLAYERKIT_HLS_SMOKE_URL to exercise the real AVFoundation path.
        guard let rawURL = ProcessInfo.processInfo.environment["PLAYERKIT_HLS_SMOKE_URL"] else {
            throw XCTSkip("Set PLAYERKIT_HLS_SMOKE_URL to run the real HLS metrics smoke test.")
        }
        guard let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            XCTFail("PLAYERKIT_HLS_SMOKE_URL must be a remote HTTP(S) URL.")
            return
        }

        let manager = PlayerManager.shared
        manager.isPlaybackHealthMonitoringEnabled = true
        manager.setPlayer(type: .avPlayer)
        manager.load(
            playerItem: PlayerItem(
                title: "HLS metrics smoke",
                url: url,
                playbackHealthAssetIdentifier: "real-hls-smoke",
                playbackHealthMonitoringEligible: true
            )
        )
        manager.play()
        defer {
            manager.stop()
            manager.resetPlayer()
            manager.isPlaybackHealthMonitoringEnabled = false
        }

        let deadline = Date().addingTimeInterval(30)
        var snapshot = manager.fetchPlaybackDiagnostics()
        while Date() < deadline {
            let observedSegments = snapshot.monitor?.segmentRequestCount ?? 0
            if snapshot.session.monitorAttached,
               snapshot.playback.isLikelyHLS == true,
               observedSegments > 0,
               snapshot.network.accessLogEventCount > 0 {
                break
            }
            try await Task.sleep(nanoseconds: 250_000_000)
            snapshot = manager.fetchPlaybackDiagnostics()
        }

        XCTAssertTrue(snapshot.session.monitorAttached)
        XCTAssertEqual(snapshot.session.availability, .activeAVMetrics)
        XCTAssertEqual(snapshot.playback.isLikelyHLS, true)
        XCTAssertGreaterThan(snapshot.monitor?.segmentRequestCount ?? 0, 0)
        XCTAssertGreaterThan(snapshot.network.accessLogEventCount, 0)
        XCTAssertTrue(snapshot.session.assetIdentifier?.hasPrefix("sha256:") == true)

        let report = snapshot.report()
        XCTAssertFalse(report.contains(rawURL))
        XCTAssertFalse(report.contains(url.host ?? rawURL))
        for secret in URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .compactMap(\.value)
            .filter({ $0.utf8.count >= 8 }) ?? [] {
            XCTAssertFalse(report.contains(secret))
        }
    }

    private func reportSample(
        id: UUID,
        capturedAt: Date,
        mediaTime: Double
    ) -> PlaybackDiagnosticsSample {
        PlaybackDiagnosticsSample(
            id: id,
            capturedAt: capturedAt,
            sessionElapsed: capturedAt.timeIntervalSince1970 - 100,
            mediaTime: mediaTime,
            state: .playing,
            waitingReason: nil,
            playbackRate: 1,
            isPlaybackLikelyToKeepUp: true,
            isPlaybackBufferEmpty: false,
            isPlaybackBufferFull: false,
            bufferHeadroom: 20,
            observedBitRate: 5_000_000,
            indicatedBitRate: 4_000_000,
            resolution: "1920×1080",
            frameRate: 24,
            droppedVideoFrameCount: 1,
            droppedVideoFrameDelta: 0,
            renditionPeakBitRate: 5_000_000,
            renditionAverageBitRate: 4_000_000,
            renditionResolution: "1920×1080",
            renditionFrameRate: 24,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000042"),
            assetIdentifier: "sha256:asset",
            availability: .activeAVMetrics
        )
    }

    private func reportIncident(
        id: UUID,
        startedAt: Date,
        evidenceIDs: [UUID],
        measuredValues: [String]
    ) -> PlaybackDiagnosticsAutomaticIncident {
        PlaybackDiagnosticsAutomaticIncident(
            id: id,
            kind: .repeatedRequestFailures,
            severity: .warning,
            startedAt: startedAt,
            lastObservedAt: startedAt.addingTimeInterval(1),
            endedAt: startedAt.addingTimeInterval(2),
            impact: "Multiple requests failed.",
            likelyCause: "Correlated request failures were measured.",
            evidenceIDs: evidenceIDs,
            measuredValues: measuredValues,
            nextAction: "Inspect request timing.",
            evidenceStrength: .correlated
        )
    }

    private func reportBookmark(
        id: UUID,
        capturedAt: Date,
        nearbySampleIDs: [UUID],
        nearbyEvidenceIDs: [UUID]
    ) -> PlaybackDiagnosticsBookmark {
        PlaybackDiagnosticsBookmark(
            id: id,
            capturedAt: capturedAt,
            sessionElapsed: capturedAt.timeIntervalSince1970 - 100,
            mediaTime: capturedAt.timeIntervalSince1970 - 100,
            nearbySampleIDs: nearbySampleIDs,
            nearbyEvidenceIDs: nearbyEvidenceIDs,
            selectedAudioTrack: PlaybackDiagnosticsTrack(
                identifier: "sha256:audio-a",
                name: "Selected audio track",
                languageCode: "en",
                isSelected: true
            ),
            itemStatus: "ready",
            timeControlStatus: "playing",
            waitingReason: nil,
            bufferHeadroom: 20,
            resolution: "1920×1080",
            frameRate: 24,
            observedBitRate: 5_000_000,
            indicatedBitRate: 4_000_000,
            accessLogStallCount: 1,
            metricStallCount: 1,
            observedHLSRequestCount: 10,
            failedHLSRequestCount: 2,
            postStartWaitCount: 1,
            seekWaitCount: 0,
            errorLogEventCount: 1
        )
    }

    private func makeSnapshot(
        availability: PlaybackDiagnosticsAvailability = .activeAVMetrics,
        capturedAt: Date = Date(timeIntervalSince1970: 200),
        playback: PlaybackDiagnosticsSnapshot.Playback? = nil,
        network: PlaybackDiagnosticsSnapshot.Network? = nil,
        audioTracks: [PlaybackDiagnosticsTrack]? = nil,
        subtitleTracks: [PlaybackDiagnosticsTrack] = [],
        errors: [PlaybackDiagnosticsError] = [],
        events: [PlaybackHealthEvent] = [],
        monitor: PlaybackHealthMonitorTelemetry = .initial(for: .observing),
        history: PlaybackDiagnosticsHistory? = nil,
        storyboard: PlaybackDiagnosticsStoryboard = .empty
    ) -> PlaybackDiagnosticsSnapshot {
        PlaybackDiagnosticsSnapshot(
            session: PlaybackDiagnosticsSnapshot.Session(
                capturedAt: capturedAt,
                availability: availability,
                backend: "AVPlayer",
                monitorAttached: true,
                sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000042"),
                assetIdentifier: "42"
            ),
            playback: playback ?? makePlayback(),
            network: network ?? makeNetwork(),
            audioTracks: audioTracks ?? [
                PlaybackDiagnosticsTrack(
                    identifier: "sha256:0123456789abcdef",
                    name: "Russian",
                    languageCode: "ru",
                    isSelected: true
                )
            ],
            subtitleTracks: subtitleTracks,
            errorLogEventCount: errors.count,
            recentErrors: errors,
            recentHealthEvents: events,
            monitor: monitor,
            history: history ?? PlaybackDiagnosticsHistory(
                    receivedCount: events.count,
                    retainedCount: events.count,
                    droppedCount: 0,
                    clearedCount: 0
                ),
            storyboard: storyboard
        )
    }

    private func makePlayback(
        itemStatus: String = "ready",
        timeControlStatus: String = "paused",
        isPlaybackBufferEmpty: Bool = false,
        isLikelyHLS: Bool? = true,
        isMuted: Bool = false,
        volume: Double = 1,
        currentTime: Double = 10,
        duration: Double = 120,
        isPlaybackLikelyToKeepUp: Bool = true,
        bufferedUntil: Double? = nil,
        bufferHeadroom: Double? = nil
    ) -> PlaybackDiagnosticsSnapshot.Playback {
        PlaybackDiagnosticsSnapshot.Playback(
            itemStatus: itemStatus,
            timeControlStatus: timeControlStatus,
            waitingReason: nil,
            rate: timeControlStatus == "playing" ? 1 : 0,
            currentTime: currentTime,
            duration: duration,
            bufferedUntil: bufferedUntil ?? (isPlaybackBufferEmpty ? nil : 30),
            bufferHeadroom: bufferHeadroom ?? (isPlaybackBufferEmpty ? 0 : 20),
            loadedRangeCount: isPlaybackBufferEmpty ? 0 : 1,
            seekableRangeCount: 1,
            isPlaybackLikelyToKeepUp: isPlaybackLikelyToKeepUp,
            isPlaybackBufferEmpty: isPlaybackBufferEmpty,
            isPlaybackBufferFull: false,
            automaticallyWaitsToMinimizeStalling: true,
            isMuted: isMuted,
            volume: volume,
            playbackType: "VOD",
            isLikelyHLS: isLikelyHLS,
            resolution: "1920×1080",
            frameRate: 24,
            preferredForwardBufferDuration: 0,
            preferredPeakBitRate: 0,
            preferredMaximumResolution: nil
        )
    }

    private func makeNetwork(
        mediaRequestCount: Int? = 10,
        numberOfStalls: Int? = 0,
        droppedVideoFrameCount: Int? = 0,
        overdueDownloadCount: Int? = 0,
        bytesTransferred: Int64? = 1_000_000,
        transferDuration: Double? = 1,
        observedBitRate: Double? = 5_000_000,
        indicatedBitRate: Double? = 4_000_000,
        segmentsDownloadedDuration: Double? = 20,
        durationWatched: Double? = 10,
        startupTime: Double? = 1,
        serverAddressChangeCount: Int? = 0
    ) -> PlaybackDiagnosticsSnapshot.Network {
        PlaybackDiagnosticsSnapshot.Network(
            accessLogEventCount: 1,
            mediaRequestCount: mediaRequestCount,
            numberOfStalls: numberOfStalls,
            droppedVideoFrameCount: droppedVideoFrameCount,
            overdueDownloadCount: overdueDownloadCount,
            bytesTransferred: bytesTransferred,
            transferDuration: transferDuration,
            observedBitRate: observedBitRate,
            indicatedBitRate: indicatedBitRate,
            indicatedAverageBitRate: indicatedBitRate,
            averageVideoBitRate: indicatedBitRate,
            averageAudioBitRate: 128_000,
            observedBitRateStandardDeviation: 100_000,
            switchBitRate: nil,
            segmentsDownloadedDuration: segmentsDownloadedDuration,
            durationWatched: durationWatched,
            startupTime: startupTime,
            serverAddressChangeCount: serverAddressChangeCount
        )
    }

    private func healthEvent(
        sessionID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!,
        mediaTime: Double = 10,
        confidence: PlaybackHealthConfidence,
        mediaType: PlaybackHealthMediaType,
        selectedAudioTrack: PlaybackHealthAudioTrack? = nil
    ) -> PlaybackHealthEvent {
        PlaybackHealthEvent(
            healthSessionID: sessionID,
            assetIdentifier: "42",
            signalKind: .mediaSegmentRequestFailure,
            confidence: confidence,
            mediaType: mediaType,
            mediaTime: mediaTime,
            selectedAudioTrack: selectedAudioTrack,
            errorDomain: NSURLErrorDomain,
            errorCode: URLError.timedOut.rawValue,
            didRecover: false,
            occurredAt: Date(timeIntervalSince1970: mediaTime)
        )
    }

    private func requestTraceEntry(index: Int) -> PlaybackHealthRequestTraceEntry {
        PlaybackHealthRequestTraceEntry(
            kind: .contentKey,
            mediaType: .audio,
            occurredAt: Date(timeIntervalSince1970: Double(index) + 0.125),
            didFail: index.isMultiple(of: 2),
            didRecover: index.isMultiple(of: 3),
            requestDuration: 0.4,
            timeToFirstByte: 0.1,
            transferDuration: 0.3,
            httpStatusCode: 200,
            mimeCategory: .binary,
            wasReadFromCache: false,
            redirectCount: 0,
            networkProtocol: "h2",
            responseBodyBytes: 1_024,
            decodedBodyBytes: 1_024,
            reusedConnection: true,
            proxyConnection: false,
            constrainedNetwork: false,
            expensiveNetwork: false,
            cellularNetwork: false,
            multipathConnection: false,
            fetchType: .networkLoad,
            segmentDeliveryRatio: nil
        )
    }
}
#endif
