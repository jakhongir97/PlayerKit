#if os(macOS)
import AVFoundation
import Foundation
import XCTest
@testable import PlayerKit

final class PlaybackHealthClassifierTests: XCTestCase {
    func testNonRecoveredAudioFailureIsHighConfidenceAndSanitized() async {
        let sessionID = UUID()
        let classifier = MacOSPlaybackHealthClassifier(
            healthSessionID: sessionID,
            assetIdentifier: "42"
        )

        let event = await classifier.classify(
            snapshot(
                sessionID: sessionID,
                mediaTime: 12.349,
                errorDomain: "CoreMediaErrorDomain",
                errorCode: -12880,
                didRecover: false
            )
        )

        XCTAssertEqual(event?.assetIdentifier, "42")
        XCTAssertEqual(event?.confidence, .high)
        XCTAssertEqual(event?.mediaType, .audio)
        XCTAssertEqual(event?.mediaTime, 12.3)
        XCTAssertEqual(event?.errorDomain, "CoreMediaErrorDomain")
        XCTAssertEqual(event?.errorCode, -12880)
        XCTAssertEqual(event?.didRecover, false)
        XCTAssertNil(event?.selectedAudioTrack?.displayName)
    }

    func testRecoveredThenNonRecoveredAudioSamplesProgressFromMediumToHigh() async {
        let sessionID = UUID()
        let classifier = MacOSPlaybackHealthClassifier(
            healthSessionID: sessionID,
            assetIdentifier: "42"
        )

        let recovered = await classifier.classify(
            snapshot(
                sessionID: sessionID,
                errorDomain: NSURLErrorDomain,
                errorCode: URLError.timedOut.rawValue,
                didRecover: true
            )
        )
        let nonRecovered = await classifier.classify(
            snapshot(
                sessionID: sessionID,
                selectedTrackIdentifier: "sha256:another-track",
                errorDomain: NSURLErrorDomain,
                errorCode: URLError.timedOut.rawValue,
                didRecover: false
            )
        )

        XCTAssertEqual(recovered?.confidence, .medium)
        XCTAssertEqual(nonRecovered?.confidence, .high)
    }

    func testRepeatedCandidateIsSessionDeduplicated() async {
        let sessionID = UUID()
        let classifier = MacOSPlaybackHealthClassifier(
            healthSessionID: sessionID,
            assetIdentifier: "42"
        )
        let sample = snapshot(
            sessionID: sessionID,
            errorDomain: NSURLErrorDomain,
            errorCode: URLError.networkConnectionLost.rawValue,
            didRecover: true
        )

        let first = await classifier.classify(sample)
        let second = await classifier.classify(sample)

        XCTAssertNotNil(first)
        XCTAssertNil(second)
        let telemetry = await classifier.telemetry()
        XCTAssertEqual(telemetry.candidateCount, 2)
        XCTAssertEqual(telemetry.emittedCount, 1)
        XCTAssertEqual(telemetry.suppressedCount, 1)
    }

    func testCalibrationSampleCapBoundsEventVolume() async {
        let sessionID = UUID()
        let classifier = MacOSPlaybackHealthClassifier(
            healthSessionID: sessionID,
            assetIdentifier: "42"
        )
        var emittedCount = 0

        for index in 0...MacOSPlaybackHealthClassifier.calibrationSampleCap {
            let event = await classifier.classify(
                snapshot(
                    sessionID: sessionID,
                    mediaTime: Double(index),
                    selectedTrackIdentifier: "sha256:track-\(index)",
                    occurredAt: Date(timeIntervalSince1970: Double(index))
                )
            )
            if event != nil {
                emittedCount += 1
            }
        }

        XCTAssertEqual(emittedCount, MacOSPlaybackHealthClassifier.calibrationSampleCap)
        let telemetry = await classifier.telemetry()
        XCTAssertEqual(telemetry.candidateCount, MacOSPlaybackHealthClassifier.calibrationSampleCap + 1)
        XCTAssertEqual(telemetry.emittedCount, MacOSPlaybackHealthClassifier.calibrationSampleCap)
        XCTAssertEqual(telemetry.suppressedCount, 1)
        XCTAssertTrue(telemetry.sampleCapReached)
    }

    func testRequestTimingSanitizerRejectsNegativeOrdering() {
        let start = Date(timeIntervalSince1970: 10)

        XCTAssertEqual(
            sanitizedPlaybackHealthInterval(
                from: start,
                to: Date(timeIntervalSince1970: 10.25)
            ) ?? -1,
            0.25,
            accuracy: 0.0001
        )
        XCTAssertNil(
            sanitizedPlaybackHealthInterval(
                from: start,
                to: Date(timeIntervalSince1970: 9)
            )
        )
    }

    func testStaleSessionAndInvalidatedClassifierRejectLateSamples() async {
        let sessionID = UUID()
        let classifier = MacOSPlaybackHealthClassifier(
            healthSessionID: sessionID,
            assetIdentifier: "42"
        )

        let stale = await classifier.classify(snapshot(sessionID: UUID()))
        await classifier.invalidate()
        let invalidated = await classifier.classify(snapshot(sessionID: sessionID))

        XCTAssertNil(stale)
        XCTAssertNil(invalidated)
    }

    func testUnsafeDomainIsRemovedButNumericCodeIsPreserved() async {
        let sessionID = UUID()
        let classifier = MacOSPlaybackHealthClassifier(
            healthSessionID: sessionID,
            assetIdentifier: "42"
        )

        let event = await classifier.classify(
            snapshot(
                sessionID: sessionID,
                errorDomain: "https://media.example/segment?token=secret",
                errorCode: 403,
                didRecover: false
            )
        )

        XCTAssertNil(event?.errorDomain)
        XCTAssertEqual(event?.errorCode, 403)
    }

    func testUnlistedDomainIsRemovedButNumericCodeIsPreserved() async {
        let sessionID = UUID()
        let classifier = MacOSPlaybackHealthClassifier(
            healthSessionID: sessionID,
            assetIdentifier: "42"
        )

        let event = await classifier.classify(
            snapshot(
                sessionID: sessionID,
                errorDomain: "ExamplePlaybackErrorDomain",
                errorCode: 123,
                didRecover: false
            )
        )

        XCTAssertNil(event?.errorDomain)
        XCTAssertEqual(event?.errorCode, 123)
    }

    func testStallIsLowConfidenceContext() async {
        let sessionID = UUID()
        let classifier = MacOSPlaybackHealthClassifier(
            healthSessionID: sessionID,
            assetIdentifier: "42"
        )

        let event = await classifier.classify(
            snapshot(
                sessionID: sessionID,
                signalKind: .playbackStall,
                mediaType: .unknown,
                errorDomain: nil,
                errorCode: nil,
                didRecover: nil
            )
        )

        XCTAssertEqual(event?.confidence, .low)
        XCTAssertEqual(event?.signalKind, .playbackStall)
    }

    func testMuxedFailureIsNotRelabeledAsAudio() async {
        let sessionID = UUID()
        let classifier = MacOSPlaybackHealthClassifier(
            healthSessionID: sessionID,
            assetIdentifier: "42"
        )

        let event = await classifier.classify(
            snapshot(
                sessionID: sessionID,
                mediaType: .muxed,
                didRecover: false
            )
        )

        XCTAssertEqual(event?.mediaType, .muxed)
        XCTAssertEqual(event?.confidence, .medium)
    }

    func testContentKeyFailureIsExcludedFromHealthClassification() async {
        let sessionID = UUID()
        let classifier = MacOSPlaybackHealthClassifier(
            healthSessionID: sessionID,
            assetIdentifier: "42"
        )

        let recovered = await classifier.classify(
            snapshot(
                sessionID: sessionID,
                signalKind: .contentKeyRequestFailure,
                mediaType: .video,
                errorDomain: "https://keys.example/key?token=secret",
                didRecover: true
            )
        )
        let unrecovered = await classifier.classify(
            snapshot(
                sessionID: sessionID,
                signalKind: .contentKeyRequestFailure,
                mediaType: .unknown,
                errorDomain: "private.key.domain",
                didRecover: false
            )
        )
        let unknownRecovery = await classifier.classify(
            snapshot(
                sessionID: sessionID,
                signalKind: .contentKeyRequestFailure,
                mediaType: .audio,
                errorDomain: nil,
                didRecover: nil
            )
        )

        XCTAssertNil(recovered)
        XCTAssertNil(unrecovered)
        XCTAssertNil(unknownRecovery)
        let telemetry = await classifier.telemetry()
        XCTAssertEqual(telemetry.candidateCount, 3)
        XCTAssertEqual(telemetry.emittedCount, 0)
        XCTAssertEqual(telemetry.suppressedCount, 3)
    }

    func testInitialLikelyToKeepUpReducerDoesNotDoubleCountNestedRequests() {
        var telemetry = PlaybackHealthMonitorTelemetry.initial(for: .observing)
        telemetry.playlistRequestCount = 5
        telemetry.segmentRequestCount = 20
        telemetry.contentKeys.record(
            mediaType: .audio,
            failed: false,
            clientInitiated: false
        )
        let initialRequests = PlaybackHealthInitialRequestTelemetry(
            playlists: PlaybackHealthRequestTimingAggregate(
                requestDurations: [0.1, nil]
            ),
            segments: PlaybackHealthRequestTimingAggregate(
                requestDurations: [0.2, 0.3, -.infinity]
            ),
            contentKeys: PlaybackHealthRequestTimingAggregate(
                requestDurations: [0.4]
            )
        )

        telemetry.likelyToKeepUp.record(
            occurredAt: Date(timeIntervalSince1970: 10),
            mediaTime: 0,
            timeTaken: 1.5,
            loadedRangeDuration: 12,
            initialRequests: initialRequests
        )
        telemetry.likelyToKeepUp.record(
            occurredAt: Date(timeIntervalSince1970: 20),
            mediaTime: 10,
            timeTaken: 0.5,
            loadedRangeDuration: 8,
            initialRequests: nil
        )

        XCTAssertEqual(telemetry.playlistRequestCount, 5)
        XCTAssertEqual(telemetry.segmentRequestCount, 20)
        XCTAssertEqual(telemetry.contentKeys.totalCount, 1)
        XCTAssertEqual(telemetry.likelyToKeepUp.eventCount, 2)
        XCTAssertEqual(telemetry.likelyToKeepUp.initial?.timeTaken, 1.5)
        XCTAssertEqual(telemetry.likelyToKeepUp.latest?.timeTaken, 0.5)
        XCTAssertEqual(
            telemetry.likelyToKeepUp.initialRequests?.segments.requestCount,
            3
        )
        XCTAssertEqual(
            telemetry.likelyToKeepUp.initialRequests?.segments.durationSampleCount,
            2
        )
        XCTAssertEqual(
            telemetry.likelyToKeepUp.initialRequests?.segments.summedRequestDuration ?? -1,
            0.5,
            accuracy: 0.0001
        )
    }

    func testSeekStartReclassifiesOpenPostStartWaitAndTracksBackToBackSeeks() {
        let item = AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
        let monitor = MacOSPlaybackHealthMonitor(
            item: item,
            assetIdentifier: "42",
            selectedAudioTrackProvider: { nil },
            eventHandler: { _ in }
        )
        defer { monitor.stop() }

        monitor.recordTimeControlStatus(
            .playing,
            waitingReason: nil,
            occurredAt: Date(timeIntervalSince1970: 1),
            systemUptime: 1
        )
        monitor.recordTimeControlStatus(
            .waitingToPlayAtSpecifiedRate,
            waitingReason: "Waiting to minimize stalls",
            occurredAt: Date(timeIntervalSince1970: 2),
            systemUptime: 2
        )
        monitor.recordSeekStarted(occurredAt: Date(timeIntervalSince1970: 2.1))
        monitor.recordSeekStarted(occurredAt: Date(timeIntervalSince1970: 2.2))

        var telemetry = monitor.telemetrySnapshot(atSystemUptime: 3)
        XCTAssertEqual(telemetry.waiting.postStartWaitCount, 0)
        XCTAssertEqual(telemetry.waiting.seekWaitCount, 1)
        XCTAssertEqual(telemetry.waiting.currentKind, .seek)
        XCTAssertEqual(telemetry.seeks.startedCount, 2)
        XCTAssertEqual(telemetry.seeks.inProgressCount, 2)

        monitor.recordSeekCompleted(
            didSeekInBuffer: false,
            occurredAt: Date(timeIntervalSince1970: 3.1)
        )
        monitor.recordSeekCompleted(
            didSeekInBuffer: true,
            occurredAt: Date(timeIntervalSince1970: 3.2)
        )
        monitor.recordTimeControlStatus(
            .playing,
            waitingReason: nil,
            occurredAt: Date(timeIntervalSince1970: 4),
            systemUptime: 4
        )

        telemetry = monitor.telemetrySnapshot(atSystemUptime: 4)
        XCTAssertEqual(telemetry.seeks.completedCount, 2)
        XCTAssertEqual(telemetry.seeks.inProgressCount, 0)
        XCTAssertEqual(telemetry.seeks.inBufferCount, 1)
        XCTAssertEqual(telemetry.seeks.outsideBufferCount, 1)
        XCTAssertEqual(telemetry.waiting.lastKind, .seek)
        XCTAssertNil(telemetry.waiting.currentKind)
    }

    func testMonitorTracksWaitEpisodesAndSanitizesTerminalFailure() {
        let item = AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
        let monitor = MacOSPlaybackHealthMonitor(
            item: item,
            assetIdentifier: "42",
            selectedAudioTrackProvider: { nil },
            eventHandler: { _ in }
        )
        defer { monitor.stop() }

        monitor.recordTimeControlStatus(
            .waitingToPlayAtSpecifiedRate,
            waitingReason: "Evaluating buffering rate",
            occurredAt: Date(timeIntervalSince1970: 10),
            systemUptime: 10
        )
        monitor.recordTimeControlStatus(
            .playing,
            waitingReason: nil,
            occurredAt: Date(timeIntervalSince1970: 12),
            systemUptime: 12
        )
        monitor.recordTimeControlStatus(
            .waitingToPlayAtSpecifiedRate,
            waitingReason: "Waiting to minimize stalls",
            occurredAt: Date(timeIntervalSince1970: 20),
            systemUptime: 20
        )
        monitor.recordTimeControlStatus(
            .paused,
            waitingReason: nil,
            occurredAt: Date(timeIntervalSince1970: 25),
            systemUptime: 25
        )
        monitor.recordTimeControlStatus(
            .waitingToPlayAtSpecifiedRate,
            waitingReason: "Waiting to minimize stalls",
            occurredAt: Date(timeIntervalSince1970: 30),
            systemUptime: 30
        )
        monitor.recordTerminalPlaybackFailure(
            error: NSError(
                domain: "https://media.example/segment?token=secret",
                code: 777
            ),
            item: item,
            occurredAt: Date(timeIntervalSince1970: 31)
        )
        monitor.recordTerminalPlaybackFailure(
            error: NSError(domain: NSURLErrorDomain, code: 888),
            item: item,
            occurredAt: Date(timeIntervalSince1970: 31.5)
        )
        monitor.recordNaturalPlaybackEnd(
            for: item,
            occurredAt: Date(timeIntervalSince1970: 32)
        )

        let telemetry = monitor.telemetrySnapshot(atSystemUptime: 33)

        XCTAssertEqual(telemetry.waiting.initialWaitCount, 1)
        XCTAssertEqual(telemetry.waiting.postStartWaitCount, 2)
        XCTAssertEqual(telemetry.waiting.currentWaitDuration ?? -1, 3, accuracy: 0.001)
        XCTAssertEqual(telemetry.waiting.totalWaitDuration, 10, accuracy: 0.001)
        XCTAssertEqual(telemetry.waiting.longestWaitDuration, 5, accuracy: 0.001)
        XCTAssertEqual(telemetry.waiting.lastWaitDuration, 5)
        XCTAssertEqual(telemetry.waiting.lastReason, "Waiting to minimize stalls")
        XCTAssertNil(telemetry.terminalFailure?.error.domain)
        XCTAssertEqual(telemetry.terminalFailure?.error.code, 777)
        XCTAssertEqual(
            telemetry.naturalEnd?.occurredAt,
            Date(timeIntervalSince1970: 32)
        )
        XCTAssertNotNil(telemetry.naturalEnd?.mediaTime)
    }

    func testNativeStallsAreAcceptedAndNearDuplicateSignalsAreSuppressed() {
        let item = AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
        let monitor = MacOSPlaybackHealthMonitor(
            item: item,
            assetIdentifier: "42",
            selectedAudioTrackProvider: { nil },
            eventHandler: { _ in }
        )
        defer { monitor.stop() }

        monitor.recordPlaybackStall(
            for: item,
            occurredAt: Date(timeIntervalSince1970: 10)
        )
        monitor.recordPlaybackStall(
            for: item,
            occurredAt: Date(timeIntervalSince1970: 10.5)
        )
        XCTAssertEqual(monitor.telemetrySnapshot.stallCount, 1)

        monitor.recordPlaybackStall(
            for: item,
            occurredAt: Date(timeIntervalSince1970: 13)
        )
        XCTAssertEqual(monitor.telemetrySnapshot.stallCount, 2)
        XCTAssertEqual(
            monitor.telemetrySnapshot.latestStallAt,
            Date(timeIntervalSince1970: 13)
        )
    }

    func testStoppedMonitorRejectsLateTelemetryMutations() {
        let item = AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
        let monitor = MacOSPlaybackHealthMonitor(
            item: item,
            assetIdentifier: "42",
            selectedAudioTrackProvider: { nil },
            eventHandler: { _ in }
        )

        monitor.stop()
        let stopped = monitor.telemetrySnapshot
        monitor.recordPlaybackStall(for: item)
        monitor.recordTerminalPlaybackFailure(
            error: NSError(domain: NSURLErrorDomain, code: 777),
            item: item
        )
        monitor.recordNaturalPlaybackEnd(for: item)
        monitor.recordSeekStarted()
        monitor.recordSeekCompleted(didSeekInBuffer: true)
        monitor.recordTimeControlStatus(
            .playing,
            waitingReason: nil
        )

        XCTAssertEqual(monitor.telemetrySnapshot, stopped)
    }

    func testNaturalEndClearsOnlyAfterMaterialResumeAndPreservesTerminalFailure() {
        let item = AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
        let monitor = MacOSPlaybackHealthMonitor(
            item: item,
            assetIdentifier: "42",
            selectedAudioTrackProvider: { nil },
            eventHandler: { _ in }
        )
        defer { monitor.stop() }

        monitor.recordTerminalPlaybackFailure(
            error: NSError(domain: NSURLErrorDomain, code: 777),
            item: item,
            occurredAt: Date(timeIntervalSince1970: 1)
        )
        monitor.recordNaturalPlaybackEnd(
            mediaTime: 120,
            occurredAt: Date(timeIntervalSince1970: 2)
        )
        monitor.recordTimeControlStatus(
            .playing,
            waitingReason: nil,
            mediaTime: 119.5,
            occurredAt: Date(timeIntervalSince1970: 3),
            systemUptime: 3
        )

        XCTAssertEqual(monitor.telemetrySnapshot.naturalEnd?.mediaTime, 120)

        monitor.recordTimeControlStatus(
            .playing,
            waitingReason: nil,
            mediaTime: 118,
            occurredAt: Date(timeIntervalSince1970: 4),
            systemUptime: 4
        )

        let resumed = monitor.telemetrySnapshot
        XCTAssertNil(resumed.naturalEnd)
        XCTAssertEqual(resumed.terminalFailure?.error.code, 777)
    }

    func testMonitorRejectsEvidenceFromForeignPlayerItem() {
        let monitoredItem = AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
        let foreignItem = AVPlayerItem(url: URL(fileURLWithPath: "/dev/zero"))
        let monitor = MacOSPlaybackHealthMonitor(
            item: monitoredItem,
            assetIdentifier: "42",
            selectedAudioTrackProvider: { nil },
            eventHandler: { _ in }
        )
        defer { monitor.stop() }

        monitor.recordTerminalPlaybackFailure(
            error: NSError(domain: NSURLErrorDomain, code: 777),
            item: foreignItem,
            occurredAt: Date(timeIntervalSince1970: 1)
        )
        monitor.recordNaturalPlaybackEnd(
            for: foreignItem,
            occurredAt: Date(timeIntervalSince1970: 2)
        )

        XCTAssertNil(monitor.telemetrySnapshot.terminalFailure)
        XCTAssertNil(monitor.telemetrySnapshot.naturalEnd)
    }

    func testPostEndReplayWaitingClearsNaturalEndBeforeWaitEarlyReturn() {
        let item = AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
        let monitor = MacOSPlaybackHealthMonitor(
            item: item,
            assetIdentifier: "42",
            selectedAudioTrackProvider: { nil },
            eventHandler: { _ in }
        )
        defer { monitor.stop() }

        monitor.recordTerminalPlaybackFailure(
            error: NSError(domain: NSURLErrorDomain, code: 777),
            item: item,
            occurredAt: Date(timeIntervalSince1970: 90)
        )
        monitor.recordNaturalPlaybackEnd(
            mediaTime: 120,
            occurredAt: Date(timeIntervalSince1970: 100)
        )
        monitor.recordTimeControlStatus(
            .waitingToPlayAtSpecifiedRate,
            waitingReason: "Evaluating buffering rate",
            mediaTime: 0,
            occurredAt: Date(timeIntervalSince1970: 101),
            systemUptime: 101
        )

        let replay = monitor.telemetrySnapshot(atSystemUptime: 102)
        XCTAssertNil(replay.naturalEnd)
        XCTAssertEqual(replay.waiting.initialWaitCount, 1)
        XCTAssertEqual(replay.terminalFailure?.error.code, 777)
    }

    func testDelayedPreEndCapturedCallbackDoesNotClearNewerNaturalEnd() {
        let item = AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
        let monitor = MacOSPlaybackHealthMonitor(
            item: item,
            assetIdentifier: "42",
            selectedAudioTrackProvider: { nil },
            eventHandler: { _ in }
        )
        defer { monitor.stop() }

        monitor.recordNaturalPlaybackEnd(
            mediaTime: 120,
            occurredAt: Date(timeIntervalSince1970: 100)
        )
        monitor.recordTimeControlStatus(
            .playing,
            waitingReason: nil,
            mediaTime: 0,
            occurredAt: Date(timeIntervalSince1970: 99),
            systemUptime: 99
        )

        XCTAssertEqual(monitor.telemetrySnapshot.naturalEnd?.mediaTime, 120)
    }

    func testFailureFingerprintDeduplicatesOnlyOneExactUnambiguousIdentity() {
        let occurredAt = Date(timeIntervalSince1970: 100)
        let rawDomain = "private.backend.error.domain"
        let rawResource = "https://media.example/segment.ts?token=secret"
        var window = PlaybackHealthFailureFingerprintWindow(
            capacity: 3,
            duplicateWindow: 2
        )

        window.record(
            rawDomain: rawDomain,
            rawResource: rawResource,
            code: 503,
            occurredAt: occurredAt
        )
        XCTAssertFalse(
            window.consumeDuplicate(
                rawDomain: nil,
                rawResource: rawResource,
                code: 503,
                occurredAt: occurredAt
            )
        )
        XCTAssertFalse(
            window.consumeDuplicate(
                rawDomain: rawDomain,
                rawResource: "https://media.example/other.ts?token=secret",
                code: 503,
                occurredAt: occurredAt
            )
        )
        XCTAssertTrue(
            window.consumeDuplicate(
                rawDomain: rawDomain,
                rawResource: rawResource,
                code: 503,
                occurredAt: occurredAt.addingTimeInterval(1)
            )
        )
        XCTAssertFalse(
            window.consumeDuplicate(
                rawDomain: rawDomain,
                rawResource: rawResource,
                code: 503,
                occurredAt: occurredAt.addingTimeInterval(1)
            )
        )

        window.record(
            rawDomain: rawDomain,
            rawResource: rawResource,
            code: 503,
            occurredAt: occurredAt
        )
        window.record(
            rawDomain: rawDomain,
            rawResource: rawResource,
            code: 503,
            occurredAt: occurredAt.addingTimeInterval(0.5)
        )
        XCTAssertFalse(
            window.consumeDuplicate(
                rawDomain: rawDomain,
                rawResource: rawResource,
                code: 503,
                occurredAt: occurredAt.addingTimeInterval(1)
            )
        )

        var rotatingTokenWindow = PlaybackHealthFailureFingerprintWindow()
        rotatingTokenWindow.record(
            rawDomain: rawDomain,
            rawResource: "https://MEDIA.example:8443/segment%20one.ts?token=alpha#first",
            code: 403,
            occurredAt: occurredAt
        )
        XCTAssertTrue(
            rotatingTokenWindow.consumeDuplicate(
                rawDomain: rawDomain,
                rawResource: "https://media.example:8443/segment%20one.ts?token=beta#second",
                code: 403,
                occurredAt: occurredAt.addingTimeInterval(1)
            )
        )
        var invalidResourceWindow = PlaybackHealthFailureFingerprintWindow()
        invalidResourceWindow.record(
            rawDomain: rawDomain,
            rawResource: "/segment%20one.ts?token=beta",
            code: 403,
            occurredAt: occurredAt
        )
        XCTAssertFalse(
            invalidResourceWindow.consumeDuplicate(
                rawDomain: rawDomain,
                rawResource: "https://media.example/segment%20one.ts",
                code: 403,
                occurredAt: occurredAt.addingTimeInterval(1)
            )
        )
    }

    func testTimeControlCallbackRejectsStaleSessionOrPlayerItem() {
        let currentSessionID = UUID()
        let currentItem = AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
        let staleItem = AVPlayerItem(url: URL(fileURLWithPath: "/dev/zero"))

        XCTAssertTrue(
            playbackHealthCallbackBelongsToCurrentSession(
                capturedSessionID: currentSessionID,
                currentSessionID: currentSessionID,
                capturedItem: currentItem,
                currentItem: currentItem
            )
        )
        XCTAssertFalse(
            playbackHealthCallbackBelongsToCurrentSession(
                capturedSessionID: UUID(),
                currentSessionID: currentSessionID,
                capturedItem: currentItem,
                currentItem: currentItem
            )
        )
        XCTAssertFalse(
            playbackHealthCallbackBelongsToCurrentSession(
                capturedSessionID: currentSessionID,
                currentSessionID: currentSessionID,
                capturedItem: staleItem,
                currentItem: currentItem
            )
        )
    }

    private func snapshot(
        sessionID: UUID,
        signalKind: PlaybackHealthSignalKind = .mediaSegmentRequestFailure,
        mediaType: PlaybackHealthMediaType = .audio,
        mediaTime: Double? = 10,
        selectedTrackIdentifier: String = "sha256:0123456789abcdef",
        errorDomain: String? = NSURLErrorDomain,
        errorCode: Int? = URLError.timedOut.rawValue,
        didRecover: Bool? = false,
        occurredAt: Date = Date(timeIntervalSince1970: 100)
    ) -> PlaybackHealthSignalSnapshot {
        PlaybackHealthSignalSnapshot(
            healthSessionID: sessionID,
            signalKind: signalKind,
            mediaType: mediaType,
            mediaTime: mediaTime,
            selectedAudioTrack: PlaybackHealthAudioTrack(
                identifier: selectedTrackIdentifier,
                languageCode: "ru",
                displayName: "Russian",
                isSelected: true
            ),
            errorDomain: errorDomain,
            errorCode: errorCode,
            didRecover: didRecover,
            occurredAt: occurredAt
        )
    }
}

@MainActor
final class PlaybackHealthIntegrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PlayerManager.shared.resetPlayer()
        PlayerManager.shared.isPlaybackHealthMonitoringEnabled = false
        PlayerManager.shared.onPlaybackHealthEvent = nil
        PlayerManager.shared.setPlayer(type: .avPlayer)
    }

    override func tearDown() {
        PlayerManager.shared.isPlaybackHealthMonitoringEnabled = false
        PlayerManager.shared.onPlaybackHealthEvent = nil
        PlayerManager.shared.resetPlayer()
        super.tearDown()
    }

    func testWrapperReplacesAndStopsExactItemMonitor() {
        let wrapper = AVPlayerWrapper()
        let firstURL = URL(string: "https://example.invalid/first.m3u8")!
        let secondURL = URL(string: "https://example.invalid/second.m3u8")!

        wrapper.load(
            url: firstURL,
            playbackHealthAssetIdentifier: "41",
            playbackHealthMonitoringEnabled: true,
            playbackHealthMonitoringEligible: true
        )
        let firstSessionID = wrapper.activePlaybackHealthSessionID

        wrapper.load(
            url: secondURL,
            playbackHealthAssetIdentifier: "42",
            playbackHealthMonitoringEnabled: true,
            playbackHealthMonitoringEligible: true
        )

        XCTAssertNotNil(firstSessionID)
        XCTAssertNotEqual(wrapper.activePlaybackHealthSessionID, firstSessionID)
        XCTAssertEqual(wrapper.activePlaybackHealthAssetIdentifier, "42")

        wrapper.stop()

        XCTAssertNil(wrapper.activePlaybackHealthSessionID)
        XCTAssertNil(wrapper.activePlaybackHealthAssetIdentifier)
    }

    func testWrapperMonitorsOnlyEligibleRemotePlayback() {
        let wrapper = AVPlayerWrapper()
        let remoteURL = URL(string: "https://example.invalid/calibration.m3u8")!

        wrapper.load(
            url: remoteURL,
            playbackHealthAssetIdentifier: nil,
            playbackHealthMonitoringEnabled: true,
            playbackHealthMonitoringEligible: true
        )
        XCTAssertNotNil(wrapper.activePlaybackHealthSessionID)
        XCTAssertTrue(
            wrapper.activePlaybackHealthAssetIdentifier?.hasPrefix("sha256:") == true
        )

        wrapper.load(
            url: remoteURL,
            playbackHealthAssetIdentifier: "42",
            playbackHealthMonitoringEnabled: true,
            playbackHealthMonitoringEligible: false
        )
        XCTAssertNil(wrapper.activePlaybackHealthSessionID)
        XCTAssertNil(wrapper.activePlaybackHealthAssetIdentifier)

        wrapper.load(
            url: URL(fileURLWithPath: "/dev/null"),
            playbackHealthAssetIdentifier: "42",
            playbackHealthMonitoringEnabled: true,
            playbackHealthMonitoringEligible: true
        )
        XCTAssertNil(wrapper.activePlaybackHealthSessionID)

        wrapper.load(url: remoteURL)
        XCTAssertNil(wrapper.activePlaybackHealthSessionID)
    }

    func testPlayerManagerPassesItemIdentityToAVPlayerWrapper() throws {
        let manager = PlayerManager.shared
        manager.isPlaybackHealthMonitoringEnabled = true
        let item = PlayerItem(
            title: "Movie",
            url: URL(string: "https://example.invalid/movie.m3u8")!,
            playbackHealthAssetIdentifier: "42",
            playbackHealthMonitoringEligible: true
        )

        manager.load(playerItem: item)

        let wrapper = try XCTUnwrap(manager.currentPlayer as? AVPlayerWrapper)
        XCTAssertEqual(wrapper.activePlaybackHealthAssetIdentifier, "42")
    }

    func testPlayerItemRebuildPreservesHealthIdentity() {
        let manager = PlayerManager.shared
        let item = PlayerItem(
            title: "Movie",
            description: "Description",
            url: URL(fileURLWithPath: "/dev/null"),
            lastPosition: 3,
            playbackHealthAssetIdentifier: "42",
            playbackHealthMonitoringEligible: true
        )

        let rebuilt = manager.makePlayerItemCopy(from: item, resumePosition: 15)

        XCTAssertEqual(rebuilt.playbackHealthAssetIdentifier, "42")
        XCTAssertTrue(rebuilt.playbackHealthMonitoringEligible)
        XCTAssertEqual(rebuilt.lastPosition, 15)
        XCTAssertEqual(rebuilt.url, item.url)
    }

    func testPlayerManagerEventCallbackSurvivesPlayerReset() {
        let manager = PlayerManager.shared
        let expectation = expectation(description: "event forwarded")
        let event = PlaybackHealthEvent(
            healthSessionID: UUID(),
            assetIdentifier: "42",
            signalKind: .mediaSegmentRequestFailure,
            confidence: .high,
            mediaType: .audio,
            mediaTime: 10,
            selectedAudioTrack: nil,
            errorDomain: NSURLErrorDomain,
            errorCode: URLError.timedOut.rawValue,
            didRecover: false,
            occurredAt: Date()
        )

        manager.onPlaybackHealthEvent = { receivedEvent in
            XCTAssertEqual(receivedEvent, event)
            expectation.fulfill()
        }
        manager.resetPlayer()
        manager.setPlayer(type: .avPlayer)

        let wrapper = manager.currentPlayer as? AVPlayerWrapper
        wrapper?.onPlaybackHealthEvent?(event)

        wait(for: [expectation], timeout: 1)
    }
}
#endif
