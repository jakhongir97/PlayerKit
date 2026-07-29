#if os(macOS)
import XCTest
@testable import PlayerKit

final class PlaybackDiagnosticsSessionReducerTests: XCTestCase {
    private let sessionID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000111"
    )!

    func testTransientLowBufferDoesNotCreateIncident() {
        var reducer = PlaybackDiagnosticsSessionReducer()
        let monitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)

        reducer.ingest(
            snapshot(
                at: 0,
                buffer: 8,
                observedBitRate: 2_000_000,
                indicatedBitRate: 4_000_000,
                monitor: monitor
            )
        )
        reducer.ingest(
            snapshot(
                at: 1,
                buffer: 1,
                observedBitRate: 2_000_000,
                indicatedBitRate: 4_000_000,
                monitor: monitor
            )
        )
        reducer.ingest(
            snapshot(
                at: 2,
                buffer: 8,
                observedBitRate: 2_000_000,
                indicatedBitRate: 4_000_000,
                monitor: monitor
            )
        )

        XCTAssertFalse(
            reducer.storyboard.incidents.contains {
                $0.kind == .deliveryStarvation
            }
        )
    }

    func testSustainedLowBufferWithDeliveryPressureCreatesOneIncident() {
        var reducer = PlaybackDiagnosticsSessionReducer()
        let monitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)

        reducer.ingest(
            snapshot(
                at: 0,
                buffer: 8,
                observedBitRate: 2_000_000,
                indicatedBitRate: 4_000_000,
                monitor: monitor
            )
        )
        for second in 1...4 {
            reducer.ingest(
                snapshot(
                    at: Double(second),
                    buffer: 1,
                    observedBitRate: 2_000_000,
                    indicatedBitRate: 4_000_000,
                    monitor: monitor
                )
            )
        }

        let starvation = reducer.storyboard.incidents.filter {
            $0.kind == .deliveryStarvation
        }
        XCTAssertEqual(starvation.count, 1)
        XCTAssertEqual(starvation.first?.state, .active)
        XCTAssertTrue(
            starvation.first?.measuredValues.contains {
                $0.contains("Observed delivery")
            } == true
        )
    }

    func testInitialAndSeekWaitsDoNotBecomeRebufferIncidents() {
        var reducer = PlaybackDiagnosticsSessionReducer()
        var monitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        reducer.ingest(snapshot(at: 0, monitor: monitor))

        monitor.stallCount = 1
        monitor.latestStallAt = date(1)
        monitor.waiting.currentKind = .initial
        reducer.ingest(
            snapshot(
                at: 1,
                state: "waiting",
                buffer: 0,
                monitor: monitor
            )
        )

        monitor.stallCount = 2
        monitor.latestStallAt = date(2)
        monitor.waiting.currentKind = .seek
        reducer.ingest(
            snapshot(
                at: 2,
                state: "waiting",
                buffer: 0,
                monitor: monitor
            )
        )

        XCTAssertFalse(
            reducer.storyboard.incidents.contains {
                $0.kind == .confirmedRebuffer
            }
        )
    }

    func testConfirmedStallOpensAndRecoveryClosesIncident() throws {
        var reducer = PlaybackDiagnosticsSessionReducer()
        var monitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        reducer.ingest(snapshot(at: 0, monitor: monitor))

        monitor.stallCount = 1
        monitor.latestStallAt = date(1)
        monitor.waiting.currentKind = .postStart
        reducer.ingest(
            snapshot(
                at: 1,
                state: "waiting",
                buffer: 0.5,
                monitor: monitor
            )
        )

        XCTAssertEqual(
            reducer.storyboard.incidents.last?.kind,
            .confirmedRebuffer
        )
        XCTAssertEqual(reducer.storyboard.incidents.last?.state, .active)

        monitor.waiting.currentKind = nil
        monitor.waiting.lastKind = .postStart
        monitor.waiting.lastEndedAt = date(3)
        monitor.waiting.lastWaitDuration = 2
        reducer.ingest(snapshot(at: 3, state: "playing", buffer: 8, monitor: monitor))
        XCTAssertEqual(
            reducer.storyboard.incidents.last {
                $0.kind == .confirmedRebuffer
            }?.state,
            .active
        )
        reducer.ingest(snapshot(at: 4, state: "playing", buffer: 8, monitor: monitor))
        XCTAssertEqual(
            reducer.storyboard.incidents.last {
                $0.kind == .confirmedRebuffer
            }?.state,
            .active
        )
        reducer.ingest(snapshot(at: 5, state: "playing", buffer: 8, monitor: monitor))

        let rebuffer = try XCTUnwrap(
            reducer.storyboard.incidents.last {
                $0.kind == .confirmedRebuffer
            }
        )
        XCTAssertEqual(rebuffer.state, .recovered)
        XCTAssertEqual(rebuffer.endedAt, date(5))
        XCTAssertTrue(
            reducer.storyboard.evidence.contains {
                $0.kind == .recovery
            }
        )

        monitor.stallCount = 2
        monitor.latestStallAt = date(10)
        monitor.waiting.currentKind = .postStart
        reducer.ingest(
            snapshot(
                at: 10,
                state: "waiting",
                buffer: 0,
                monitor: monitor
            )
        )
        XCTAssertEqual(
            reducer.storyboard.incidents.filter {
                $0.kind == .confirmedRebuffer
            }.count,
            2
        )
        XCTAssertEqual(
            reducer.storyboard.incidents.last {
                $0.kind == .confirmedRebuffer
            }?.state,
            .active
        )
    }

    func testDuplicateAndOutOfOrderSnapshotsAreIgnored() {
        var reducer = PlaybackDiagnosticsSessionReducer()
        var monitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        let initial = snapshot(at: 0, monitor: monitor)
        reducer.ingest(initial)
        reducer.ingest(initial)

        monitor.stallCount = 1
        monitor.latestStallAt = date(1)
        monitor.waiting.currentKind = .postStart
        let stalled = snapshot(
            at: 1,
            state: "waiting",
            buffer: 0,
            monitor: monitor
        )
        reducer.ingest(stalled)
        reducer.ingest(stalled)
        reducer.ingest(snapshot(at: 0.5, monitor: monitor))

        XCTAssertEqual(reducer.storyboard.samples.count, 2)
        XCTAssertEqual(
            reducer.storyboard.incidents.filter {
                $0.kind == .confirmedRebuffer
            }.count,
            1
        )
        XCTAssertEqual(
            reducer.storyboard.evidence.filter {
                $0.kind == .confirmedStall
            }.count,
            1
        )
    }

    func testLowBufferHysteresisUsesElapsedTimeNotAssumedSampleRate() {
        var reducer = PlaybackDiagnosticsSessionReducer()
        let monitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        reducer.ingest(snapshot(at: 0, monitor: monitor))

        for time in [1.0, 1.4, 2.9] {
            reducer.ingest(
                snapshot(
                    at: time,
                    buffer: 1,
                    observedBitRate: 1_000_000,
                    indicatedBitRate: 4_000_000,
                    monitor: monitor
                )
            )
        }
        XCTAssertFalse(
            reducer.storyboard.incidents.contains {
                $0.kind == .deliveryStarvation
            }
        )

        reducer.ingest(
            snapshot(
                at: 3.1,
                buffer: 1,
                observedBitRate: 1_000_000,
                indicatedBitRate: 4_000_000,
                monitor: monitor
            )
        )
        XCTAssertEqual(
            reducer.storyboard.incidents.last {
                $0.kind == .deliveryStarvation
            }?.startedAt,
            date(1)
        )
    }

    func testUserPauseDoesNotCreateRebufferOrDeliveryIncident() {
        var reducer = PlaybackDiagnosticsSessionReducer()
        var monitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        reducer.ingest(snapshot(at: 0, monitor: monitor))

        monitor.stallCount = 1
        monitor.latestStallAt = date(1)
        monitor.waiting.currentKind = .postStart
        for second in 1...4 {
            reducer.ingest(
                snapshot(
                    at: Double(second),
                    state: "paused",
                    buffer: 0,
                    observedBitRate: 1_000_000,
                    indicatedBitRate: 4_000_000,
                    monitor: monitor
                )
            )
        }

        XCTAssertFalse(
            reducer.storyboard.incidents.contains {
                $0.kind == .confirmedRebuffer
                    || $0.kind == .deliveryStarvation
            }
        )
    }

    func testRepeatedFailureEvidenceUpdatesOneIncident() throws {
        var reducer = PlaybackDiagnosticsSessionReducer()
        var monitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        reducer.ingest(snapshot(at: 0, monitor: monitor))

        for second in 1...4 {
            monitor.requestTrace.record(
                request(at: Double(second), failed: true)
            )
            monitor.failedSegmentRequestCount += 1
            monitor.segmentRequestCount += 1
            reducer.ingest(
                snapshot(
                    at: Double(second),
                    monitor: monitor
                )
            )
        }

        let failures = reducer.storyboard.incidents.filter {
            $0.kind == .repeatedRequestFailures
        }
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(try XCTUnwrap(failures.first).evidenceIDs.count, 4)
    }

    func testLaterFailureRecurrenceCreatesAnotherIncident() {
        var reducer = PlaybackDiagnosticsSessionReducer()
        var monitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        reducer.ingest(snapshot(at: 0, monitor: monitor))

        for second in 1...3 {
            monitor.requestTrace.record(
                request(at: Double(second), failed: true)
            )
            monitor.failedSegmentRequestCount += 1
            monitor.segmentRequestCount += 1
            reducer.ingest(snapshot(at: Double(second), monitor: monitor))
        }

        reducer.ingest(snapshot(at: 50, monitor: monitor))
        XCTAssertEqual(
            reducer.storyboard.incidents.last {
                $0.kind == .repeatedRequestFailures
            }?.state,
            .recovered
        )

        for second in 60...62 {
            monitor.requestTrace.record(
                request(at: Double(second), failed: true)
            )
            monitor.failedSegmentRequestCount += 1
            monitor.segmentRequestCount += 1
            reducer.ingest(snapshot(at: Double(second), monitor: monitor))
        }

        XCTAssertEqual(
            reducer.storyboard.incidents.filter {
                $0.kind == .repeatedRequestFailures
            }.count,
            2
        )
    }

    func testRequestTraceDeduplicatesClassifierEventsButKeepsDistinctRequests() {
        var reducer = PlaybackDiagnosticsSessionReducer()
        var monitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        reducer.ingest(snapshot(at: 0, monitor: monitor))

        let occurredAt = 1.0
        for _ in 0..<3 {
            monitor.requestTrace.record(
                request(at: occurredAt, failed: true)
            )
            monitor.failedSegmentRequestCount += 1
            monitor.segmentRequestCount += 1
        }
        let classifierEvent = healthEvent(
            at: occurredAt,
            kind: .mediaSegmentRequestFailure
        )
        reducer.ingest(
            snapshot(
                at: 2,
                monitor: monitor,
                healthEvents: [
                    classifierEvent,
                    classifierEvent,
                    classifierEvent
                ]
            )
        )

        XCTAssertEqual(
            reducer.storyboard.evidence.filter {
                $0.kind == .failedSegmentRequest
            }.count,
            3
        )
        XCTAssertEqual(
            reducer.storyboard.incidents.filter {
                $0.kind == .repeatedRequestFailures
            }.count,
            1
        )
    }

    func testNormalABRAdaptationIsQuietAndBoundedTransitionsDriveIncidents() {
        var reducer = PlaybackDiagnosticsSessionReducer()
        var monitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        reducer.ingest(snapshot(at: 0, monitor: monitor))

        let high = variant(bitRate: 6_000_000, resolution: "1920×1080")
        let medium = variant(bitRate: 4_000_000, resolution: "1280×720")
        let low = variant(bitRate: 2_000_000, resolution: "854×480")
        monitor.variantSwitches.record(
            from: high,
            to: medium,
            succeeded: true,
            occurredAt: date(1)
        )
        reducer.ingest(snapshot(at: 1, monitor: monitor))
        XCTAssertFalse(
            reducer.storyboard.incidents.contains {
                $0.kind == .renditionDowngrade || $0.kind == .abrThrashing
            }
        )

        monitor.variantSwitches.record(
            from: medium,
            to: low,
            succeeded: true,
            occurredAt: date(2)
        )
        reducer.ingest(snapshot(at: 2, monitor: monitor))
        XCTAssertEqual(
            reducer.storyboard.incidents.last {
                $0.kind == .renditionDowngrade
            }?.state,
            .active
        )

        monitor.variantSwitches.record(
            from: low,
            to: high,
            succeeded: true,
            occurredAt: date(3)
        )
        reducer.ingest(snapshot(at: 3, monitor: monitor))
        monitor.variantSwitches.record(
            from: high,
            to: low,
            succeeded: true,
            occurredAt: date(4)
        )
        reducer.ingest(snapshot(at: 4, monitor: monitor))

        XCTAssertEqual(
            reducer.storyboard.incidents.last {
                $0.kind == .abrThrashing
            }?.state,
            .active
        )
        XCTAssertEqual(
            reducer.storyboard.evidence.filter {
                $0.kind == .variantSwitch
            }.count,
            4
        )
    }

    func testPointEvidenceCorrelatesWithinThirtySeconds() {
        var reducer = PlaybackDiagnosticsSessionReducer()
        var monitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        reducer.ingest(snapshot(at: 0, monitor: monitor))

        for second in [1.0, 20.0, 60.0] {
            monitor.requestTrace.record(
                request(
                    at: second,
                    failed: false,
                    mime: .html
                )
            )
            monitor.segmentRequestCount += 1
            reducer.ingest(snapshot(at: second, monitor: monitor))
        }

        let incidents = reducer.storyboard.incidents.filter {
            $0.kind == .unexpectedMediaResponse
        }
        XCTAssertEqual(incidents.count, 2)
        XCTAssertEqual(incidents.first?.evidenceIDs.count, 2)
        XCTAssertEqual(incidents.last?.evidenceIDs.count, 1)
    }

    func testImportantFailureSurvivesBoundedEvidenceRetention() {
        var reducer = PlaybackDiagnosticsSessionReducer()
        var monitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        monitor.contentKeys.video.record(
            failed: true,
            clientInitiated: true
        )
        reducer.ingest(snapshot(at: 0, monitor: monitor))

        for second in 1...260 {
            monitor.waiting.currentKind = second.isMultiple(of: 2) ? nil : .initial
            reducer.ingest(
                snapshot(
                    at: Double(second),
                    state: monitor.waiting.currentKind == nil ? "playing" : "waiting",
                    monitor: monitor
                )
            )
        }

        XCTAssertEqual(
            reducer.storyboard.evidence.count,
            PlaybackDiagnosticsSessionReducer.evidenceCapacity
        )
        XCTAssertTrue(
            reducer.storyboard.evidence.contains {
                $0.kind == .failedContentKeyRequest && $0.level == .critical
            }
        )
    }

    func testRoutineSuccessfulRequestsDoNotFloodEvidence() {
        var reducer = PlaybackDiagnosticsSessionReducer()
        var monitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        reducer.ingest(snapshot(at: 0, monitor: monitor))

        for second in 1...140 {
            monitor.requestTrace.record(
                request(at: Double(second), failed: false)
            )
            monitor.healthySegmentRequestCount += 1
            monitor.segmentRequestCount += 1
            reducer.ingest(snapshot(at: Double(second), monitor: monitor))
        }

        XCTAssertTrue(reducer.storyboard.evidence.isEmpty)
        XCTAssertTrue(reducer.storyboard.incidents.isEmpty)
    }

    func testUnknownMeasurementsStayOptionalAndFallbackDoesNotInventStarvation() throws {
        var reducer = PlaybackDiagnosticsSessionReducer()
        let monitor = PlaybackHealthMonitorTelemetry.initial(for: .fallbackObserving)

        for second in 0...4 {
            reducer.ingest(
                snapshot(
                    at: Double(second),
                    availability: .activeErrorLogFallback,
                    buffer: nil,
                    observedBitRate: nil,
                    indicatedBitRate: nil,
                    rate: nil,
                    monitor: monitor
                )
            )
        }

        let latest = try XCTUnwrap(reducer.storyboard.samples.last)
        XCTAssertNil(latest.bufferHeadroom)
        XCTAssertNil(latest.observedBitRate)
        XCTAssertNil(latest.indicatedBitRate)
        XCTAssertNil(latest.playbackRate)
        XCTAssertFalse(
            reducer.storyboard.incidents.contains {
                $0.kind == .deliveryStarvation
            }
        )
    }

    func testSessionMilestonesEndAndBookmarkReferencesAreMeasured() throws {
        var reducer = PlaybackDiagnosticsSessionReducer()
        var monitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        monitor.likelyToKeepUp.initial = PlaybackHealthLikelyToKeepUpSample(
            occurredAt: date(2),
            mediaTime: 12,
            timeTaken: 2,
            loadedRangeDuration: 8
        )
        reducer.ingest(
            snapshot(
                at: 3,
                startedAt: date(0),
                monitor: monitor
            )
        )
        monitor.requestTrace.record(request(at: 4, failed: true))
        monitor.segmentRequestCount = 1
        monitor.failedSegmentRequestCount = 1
        let current = snapshot(
            at: 4,
            startedAt: date(0),
            monitor: monitor
        )
        reducer.ingest(current)

        let bookmark = try XCTUnwrap(
            reducer.captureBookmark(from: current, at: date(4.5))
        )
        XCTAssertEqual(reducer.storyboard.sessionStartedAt, date(0))
        XCTAssertEqual(reducer.storyboard.firstPlayingAt, date(3))
        XCTAssertEqual(reducer.storyboard.firstLikelyToKeepUpAt, date(2))
        XCTAssertEqual(reducer.storyboard.samples.first?.sessionElapsed, 3)
        XCTAssertEqual(bookmark.sessionElapsed, 4.5)
        XCTAssertEqual(bookmark.observedHLSRequestCount, 1)
        XCTAssertEqual(bookmark.failedHLSRequestCount, 1)
        XCTAssertFalse(bookmark.nearbySampleIDs.isEmpty)
        XCTAssertFalse(bookmark.nearbyEvidenceIDs.isEmpty)
        XCTAssertLessThanOrEqual(
            bookmark.nearbySampleIDs.count,
            PlaybackDiagnosticsSessionReducer.bookmarkReferenceCapacity
        )
        XCTAssertLessThanOrEqual(
            bookmark.nearbyEvidenceIDs.count,
            PlaybackDiagnosticsSessionReducer.bookmarkReferenceCapacity
        )

        reducer.end(at: date(6))
        reducer.end(at: date(7))
        XCTAssertEqual(reducer.storyboard.endedAt, date(6))
    }

    func testFallbackTerminalFailureUsesSanitizedErrorAndIsIdempotent() {
        let error = PlaybackDiagnosticsError(
            occurredAt: date(1),
            domain: NSURLErrorDomain,
            code: URLError.timedOut.rawValue
        )
        var reducer = PlaybackDiagnosticsSessionReducer()
        let failed = snapshot(
            at: 1,
            itemStatus: "failed",
            monitor: nil,
            recentErrors: [error]
        )
        reducer.ingest(failed)
        reducer.ingest(
            snapshot(
                at: 2,
                itemStatus: "failed",
                monitor: nil,
                recentErrors: [error]
            )
        )

        XCTAssertEqual(reducer.storyboard.samples.count, 1)
        XCTAssertEqual(
            reducer.storyboard.evidence.filter {
                $0.kind == .terminalFailure
            }.count,
            1
        )
        XCTAssertEqual(
            reducer.storyboard.evidence.last {
                $0.kind == .terminalFailure
            }?.measurement,
            "\(NSURLErrorDomain) / \(URLError.timedOut.rawValue)"
        )
        XCTAssertEqual(
            reducer.storyboard.incidents.filter {
                $0.kind == .terminalFailure
            }.count,
            1
        )
        XCTAssertEqual(reducer.storyboard.endedAt, date(1))

        var unavailableReducer = PlaybackDiagnosticsSessionReducer()
        unavailableReducer.ingest(
            snapshot(
                at: 1,
                itemStatus: "failed",
                monitor: nil
            )
        )
        XCTAssertEqual(
            unavailableReducer.storyboard.evidence.last {
                $0.kind == .terminalFailure
            }?.measurement,
            "Error details unavailable"
        )
    }

    func testStableIDsAndChronologicalEvidenceAreReproducible() {
        func reduce() -> PlaybackDiagnosticsStoryboard {
            var reducer = PlaybackDiagnosticsSessionReducer()
            var monitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)
            reducer.ingest(snapshot(at: 0, monitor: monitor))
            for second in [8.0, 7.0, 9.0] {
                monitor.requestTrace.record(
                    request(at: second, failed: true)
                )
                monitor.segmentRequestCount += 1
                monitor.failedSegmentRequestCount += 1
            }
            reducer.ingest(snapshot(at: 10, monitor: monitor))
            return reducer.storyboard
        }

        let first = reduce()
        let second = reduce()
        XCTAssertEqual(first, second)
        XCTAssertEqual(
            first.evidence
                .filter { $0.kind == .failedSegmentRequest }
                .map(\.occurredAt),
            [date(7), date(8), date(9)]
        )
        XCTAssertEqual(
            first.incidents.last {
                $0.kind == .repeatedRequestFailures
            }?.startedAt,
            date(7)
        )
    }

    func testCollectionAndIncidentPayloadsStayBoundedWithoutDanglingReferences() {
        var reducer = PlaybackDiagnosticsSessionReducer()
        var monitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        reducer.ingest(snapshot(at: 0, monitor: monitor))

        for second in 1...304 {
            if second <= 40 {
                monitor.requestTrace.record(
                    request(at: Double(second), failed: true)
                )
                monitor.segmentRequestCount += 1
                monitor.failedSegmentRequestCount += 1
            }
            reducer.ingest(snapshot(at: Double(second), monitor: monitor))
        }

        XCTAssertEqual(
            reducer.storyboard.samples.count,
            PlaybackDiagnosticsSessionReducer.sampleCapacity
        )
        let incident = reducer.storyboard.incidents.last {
            $0.kind == .repeatedRequestFailures
        }
        XCTAssertLessThanOrEqual(
            incident?.evidenceIDs.count ?? 0,
            PlaybackDiagnosticsSessionReducer.incidentEvidenceCapacity
        )
        XCTAssertLessThanOrEqual(
            incident?.measuredValues.count ?? 0,
            PlaybackDiagnosticsSessionReducer.incidentMeasurementCapacity
        )
        let evidenceIDs = Set(reducer.storyboard.evidence.map(\.id))
        XCTAssertTrue(
            reducer.storyboard.incidents
                .flatMap(\.evidenceIDs)
                .allSatisfy(evidenceIDs.contains)
        )
    }

    func testSessionChangeResetsSamplesAndIncidents() {
        var reducer = PlaybackDiagnosticsSessionReducer()
        var monitor = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        reducer.ingest(snapshot(at: 0, monitor: monitor))

        monitor.stallCount = 1
        monitor.latestStallAt = date(1)
        monitor.waiting.currentKind = .postStart
        reducer.ingest(
            snapshot(
                at: 1,
                state: "waiting",
                buffer: 0,
                monitor: monitor
            )
        )
        XCTAssertFalse(reducer.storyboard.incidents.isEmpty)
        XCTAssertNotNil(
            reducer.captureBookmark(
                from: snapshot(at: 1, monitor: monitor),
                at: date(1.5)
            )
        )

        let nextSessionID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000222"
        )!
        reducer.ingest(
            snapshot(
                at: 2,
                sessionID: nextSessionID,
                assetIdentifier: "sha256:new-item",
                monitor: .initial(for: .observing)
            )
        )

        XCTAssertEqual(reducer.storyboard.samples.count, 1)
        XCTAssertEqual(reducer.storyboard.samples.first?.sessionID, nextSessionID)
        XCTAssertTrue(reducer.storyboard.incidents.isEmpty)
        XCTAssertTrue(reducer.storyboard.evidence.isEmpty)
        XCTAssertTrue(reducer.storyboard.bookmarks.isEmpty)
    }

    private func snapshot(
        at seconds: Double,
        startedAt: Date? = nil,
        sessionID: UUID? = nil,
        assetIdentifier: String = "sha256:item",
        availability: PlaybackDiagnosticsAvailability = .activeAVMetrics,
        itemStatus: String = "ready",
        state: String = "playing",
        buffer: Double? = 8,
        observedBitRate: Double? = 4_000_000,
        indicatedBitRate: Double? = 4_000_000,
        rate: Double? = 1,
        droppedVideoFrameCount: Int? = nil,
        monitor: PlaybackHealthMonitorTelemetry?,
        recentErrors: [PlaybackDiagnosticsError] = [],
        healthEvents: [PlaybackHealthEvent] = []
    ) -> PlaybackDiagnosticsSnapshot {
        PlaybackDiagnosticsSnapshot(
            session: PlaybackDiagnosticsSnapshot.Session(
                capturedAt: date(seconds),
                startedAt: startedAt ?? date(0),
                availability: availability,
                backend: "AVPlayer",
                monitorAttached: monitor != nil,
                sessionID: sessionID ?? self.sessionID,
                assetIdentifier: assetIdentifier
            ),
            playback: PlaybackDiagnosticsSnapshot.Playback(
                itemStatus: itemStatus,
                timeControlStatus: state,
                waitingReason: state == "waiting" ? "minimizeStalls" : nil,
                rate: rate,
                currentTime: 10 + seconds,
                duration: 120,
                bufferedUntil: buffer.map { 10 + seconds + $0 },
                bufferHeadroom: buffer,
                loadedRangeCount: buffer == nil ? 0 : 1,
                seekableRangeCount: 1,
                isPlaybackLikelyToKeepUp: (buffer ?? 0) > 2,
                isPlaybackBufferEmpty: buffer == 0,
                isPlaybackBufferFull: false,
                automaticallyWaitsToMinimizeStalling: true,
                isMuted: false,
                volume: 1,
                playbackType: "VOD",
                isLikelyHLS: true,
                resolution: "1920×1080",
                frameRate: 25,
                preferredForwardBufferDuration: 0,
                preferredPeakBitRate: 0,
                preferredMaximumResolution: nil
            ),
            network: PlaybackDiagnosticsSnapshot.Network(
                accessLogEventCount: 1,
                mediaRequestCount: monitor?.segmentRequestCount,
                numberOfStalls: monitor?.stallCount,
                droppedVideoFrameCount: droppedVideoFrameCount,
                overdueDownloadCount: nil,
                bytesTransferred: nil,
                transferDuration: nil,
                observedBitRate: observedBitRate,
                indicatedBitRate: indicatedBitRate,
                indicatedAverageBitRate: indicatedBitRate,
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
            errorLogEventCount: recentErrors.count,
            recentErrors: recentErrors,
            recentHealthEvents: healthEvents,
            monitor: monitor,
            history: .empty,
            storyboard: .empty
        )
    }

    private func request(
        at seconds: Double,
        failed: Bool,
        mime: PlaybackHealthMIMECategory = .transportStream
    ) -> PlaybackHealthRequestTraceEntry {
        PlaybackHealthRequestTraceEntry(
            kind: .segment,
            mediaType: .video,
            occurredAt: date(seconds),
            didFail: failed,
            didRecover: failed ? false : nil,
            requestDuration: 0.4,
            timeToFirstByte: 0.1,
            transferDuration: 0.3,
            httpStatusCode: failed ? 503 : 200,
            mimeCategory: mime,
            wasReadFromCache: false,
            redirectCount: 0,
            networkProtocol: "h2",
            responseBodyBytes: nil,
            decodedBodyBytes: nil,
            reusedConnection: nil,
            proxyConnection: nil,
            constrainedNetwork: nil,
            expensiveNetwork: nil,
            cellularNetwork: nil,
            multipathConnection: nil,
            fetchType: .networkLoad,
            segmentDeliveryRatio: 0.1
        )
    }

    private func healthEvent(
        at seconds: Double,
        kind: PlaybackHealthSignalKind
    ) -> PlaybackHealthEvent {
        PlaybackHealthEvent(
            healthSessionID: sessionID,
            assetIdentifier: "sha256:item",
            signalKind: kind,
            confidence: .high,
            mediaType: .video,
            mediaTime: 10 + seconds,
            selectedAudioTrack: nil,
            errorDomain: NSURLErrorDomain,
            errorCode: URLError.badServerResponse.rawValue,
            didRecover: false,
            occurredAt: date(seconds)
        )
    }

    private func variant(
        bitRate: Double,
        resolution: String
    ) -> PlaybackHealthVariant {
        PlaybackHealthVariant(
            peakBitRate: bitRate,
            averageBitRate: bitRate,
            resolution: resolution,
            frameRate: 25
        )
    }

    private func date(_ seconds: Double) -> Date {
        Date(timeIntervalSince1970: 1_000 + seconds)
    }
}
#endif
