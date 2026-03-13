import Foundation
@preconcurrency import AVFoundation

final class DubAudioFallbackPreparedAsset: @unchecked Sendable {
    let composition: AVMutableComposition
    let temporaryDirectoryURL: URL
    let chunkCount: Int
    let coverageStartTime: Double
    let coverageEndTime: Double

    init(
        composition: AVMutableComposition,
        temporaryDirectoryURL: URL,
        chunkCount: Int,
        coverageStartTime: Double,
        coverageEndTime: Double
    ) {
        self.composition = composition
        self.temporaryDirectoryURL = temporaryDirectoryURL
        self.chunkCount = chunkCount
        self.coverageStartTime = coverageStartTime
        self.coverageEndTime = coverageEndTime
    }
}

enum DubAudioFallbackBuilder {
    private struct EmbeddedAudioChunk {
        let index: Int
        let startTime: Double
        let audioBase64: String
    }

    private enum BuildError: LocalizedError {
        case noEmbeddedAudio
        case noPlayableChunks

        var errorDescription: String? {
            switch self {
            case .noEmbeddedAudio:
                return "No embedded dubbed audio chunks were available."
            case .noPlayableChunks:
                return "Embedded dubbed audio chunks could not be prepared."
            }
        }
    }

    static func prepare(from chunks: [DubberClient.PollChunk]) async throws -> DubAudioFallbackPreparedAsset {
        let embeddedAudioChunks = chunks
            .compactMap { chunk -> EmbeddedAudioChunk? in
                guard let audioBase64 = chunk.audioBase64?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !audioBase64.isEmpty
                else {
                    return nil
                }

                let startTime = max(chunk.startTime ?? 0, 0)
                return EmbeddedAudioChunk(
                    index: chunk.index ?? 0,
                    startTime: startTime,
                    audioBase64: audioBase64
                )
            }
            .sorted {
                if $0.startTime == $1.startTime {
                    return $0.index < $1.index
                }
                return $0.startTime < $1.startTime
            }

        guard !embeddedAudioChunks.isEmpty else {
            throw BuildError.noEmbeddedAudio
        }

        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("playerkit-dub-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true
        )

        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
            throw BuildError.noPlayableChunks
        }
        var insertedChunkCount = 0
        var firstCoverageStart: Double?
        var lastCoverageEnd: Double?

        do {
            for (offset, chunk) in embeddedAudioChunks.enumerated() {
                try Task.checkCancellation()

                guard let audioData = Data(
                    base64Encoded: chunk.audioBase64,
                    options: [.ignoreUnknownCharacters]
                ), !audioData.isEmpty else {
                    continue
                }

                let chunkURL = temporaryDirectoryURL
                    .appendingPathComponent(String(format: "%03d-%03d.aac", offset, chunk.index))
                try audioData.write(to: chunkURL, options: [.atomic])

                let asset = AVURLAsset(url: chunkURL)
                let audioTracks = try await loadAudioTracks(from: asset)
                guard let sourceTrack = audioTracks.first else {
                    continue
                }

                let duration = try await loadDuration(from: asset)
                let durationSeconds = duration.seconds
                guard durationSeconds.isFinite, durationSeconds > 0 else {
                    continue
                }

                let insertionTime = CMTime(seconds: chunk.startTime, preferredTimescale: 600)
                try compositionTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: sourceTrack,
                    at: insertionTime
                )
                insertedChunkCount += 1
                firstCoverageStart = min(firstCoverageStart ?? chunk.startTime, chunk.startTime)
                lastCoverageEnd = max(lastCoverageEnd ?? (chunk.startTime + durationSeconds), chunk.startTime + durationSeconds)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
            throw error
        }

        guard insertedChunkCount > 0 else {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
            throw BuildError.noPlayableChunks
        }

        return DubAudioFallbackPreparedAsset(
            composition: composition,
            temporaryDirectoryURL: temporaryDirectoryURL,
            chunkCount: insertedChunkCount,
            coverageStartTime: firstCoverageStart ?? 0,
            coverageEndTime: lastCoverageEnd ?? 0
        )
    }

    private static func loadAudioTracks(from asset: AVAsset) async throws -> [AVAssetTrack] {
        if #available(iOS 15, tvOS 15, macOS 12, *) {
            return try await asset.loadTracks(withMediaType: .audio)
        } else {
            return asset.tracks(withMediaType: .audio)
        }
    }

    private static func loadDuration(from asset: AVAsset) async throws -> CMTime {
        if #available(iOS 15, tvOS 15, macOS 12, *) {
            return try await asset.load(.duration)
        } else {
            return asset.duration
        }
    }
}

final class DubAudioFallbackPlayer {
    private var player: AVPlayer?
    private var temporaryDirectoryURL: URL?
    private var statusObserver: NSKeyValueObservation?
    private var failedObserver: Any?
    private var stalledObserver: Any?
    private(set) var isActive: Bool = false

    var isPrepared: Bool {
        player != nil
    }

    deinit {
        stop()
    }

    func install(_ preparedAsset: DubAudioFallbackPreparedAsset) {
        stop()

        let playerItem = AVPlayerItem(asset: preparedAsset.composition)
        playerItem.audioTimePitchAlgorithm = .timeDomain

        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = false
        statusObserver = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            self?.debugLog(
                "Item status changed: \(item.status.rawValue) duration=\(item.duration.seconds) " +
                "coverage=\(preparedAsset.coverageStartTime)-\(preparedAsset.coverageEndTime) chunks=\(preparedAsset.chunkCount)"
            )
            if item.status == .failed {
                self?.debugLog("Item failed: \(item.error?.localizedDescription ?? "unknown")")
            }
        }
        failedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] notification in
            let underlyingError = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription ?? "Unknown"
            self?.debugLog("Playback failed to end: \(underlyingError)")
        }
        stalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.debugLog("Playback stalled.")
        }
        self.player = player
        temporaryDirectoryURL = preparedAsset.temporaryDirectoryURL
        debugLog(
            "Installed local fallback audio. chunks=\(preparedAsset.chunkCount) " +
            "coverage=\(preparedAsset.coverageStartTime)-\(preparedAsset.coverageEndTime)"
        )
    }

    func activate(
        at playbackTime: Double,
        isPlaying: Bool,
        isBuffering: Bool,
        playbackSpeed: Float
    ) {
        isActive = true
        debugLog("Activating local fallback audio at \(playbackTime)s")
        sync(
            to: playbackTime,
            isPlaying: isPlaying,
            isBuffering: isBuffering,
            playbackSpeed: playbackSpeed,
            forceSeek: true
        )
    }

    func sync(
        to playbackTime: Double,
        isPlaying: Bool,
        isBuffering: Bool,
        playbackSpeed: Float,
        forceSeek: Bool = false
    ) {
        guard let player else { return }

        let targetTime = max(playbackTime, 0)
        let currentTime = player.currentTime().seconds
        let shouldSeek =
            forceSeek
            || !currentTime.isFinite
            || abs(currentTime - targetTime) > 0.45

        if shouldSeek {
            let seekTime = CMTime(seconds: targetTime, preferredTimescale: 600)
            debugLog("Sync seek. current=\(currentTime) target=\(targetTime) force=\(forceSeek)")
            player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        if isBuffering || !isPlaying {
            if isBuffering {
                debugLog("Sync pause because primary video is buffering at \(targetTime)s")
            }
            player.pause()
            return
        }

        if #available(iOS 10.0, macOS 10.15, *) {
            player.playImmediately(atRate: max(playbackSpeed, 0.1))
        } else {
            player.play()
            player.rate = max(playbackSpeed, 0.1)
        }
    }

    func play(rate: Float) {
        guard let player else { return }
        isActive = true
        debugLog("Play local fallback audio. rate=\(rate)")
        if #available(iOS 10.0, macOS 10.15, *) {
            player.playImmediately(atRate: max(rate, 0.1))
        } else {
            player.play()
            player.rate = max(rate, 0.1)
        }
    }

    func pause() {
        debugLog("Pause local fallback audio.")
        player?.pause()
    }

    func seek(to playbackTime: Double) {
        guard let player else { return }
        let seekTime = CMTime(seconds: max(playbackTime, 0), preferredTimescale: 600)
        debugLog("Manual seek local fallback audio to \(playbackTime)s")
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        isActive = false
        statusObserver = nil
        if let failedObserver {
            NotificationCenter.default.removeObserver(failedObserver)
            self.failedObserver = nil
        }
        if let stalledObserver {
            NotificationCenter.default.removeObserver(stalledObserver)
            self.stalledObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil

        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        debugLog("Stopped local fallback audio.")
    }

    private func debugLog(_ message: String) {
        print("[PlayerKit][DubAudioFallback] \(message)")
    }
}
