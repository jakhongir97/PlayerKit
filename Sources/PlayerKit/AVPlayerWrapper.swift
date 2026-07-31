import AVKit
#if os(macOS)
import CryptoKit
#endif
#if canImport(UIKit)
import UIKit
#endif

#if os(macOS)
func playbackHealthCallbackBelongsToCurrentSession(
    capturedSessionID: UUID?,
    currentSessionID: UUID?,
    capturedItem: AVPlayerItem?,
    currentItem: AVPlayerItem?
) -> Bool {
    guard capturedSessionID == currentSessionID else { return false }
    if let capturedItem {
        return currentItem === capturedItem
    }
    return currentItem == nil
}

struct PlaybackDiagnosticsBufferState: Equatable, Sendable {
    let bufferedUntil: Double?
    let headroom: Double?

    static let unknown = Self(bufferedUntil: nil, headroom: nil)
    static let empty = Self(bufferedUntil: nil, headroom: 0)
}

func playbackDiagnosticsBufferState(
    currentTime: Double?,
    loadedTimeRanges: [CMTimeRange]
) -> PlaybackDiagnosticsBufferState {
    guard let currentTime,
          currentTime.isFinite,
          currentTime >= 0 else {
        return .unknown
    }

    let ranges = loadedTimeRanges.compactMap {
        range -> (start: Double, end: Double)? in
        let start = range.start.seconds
        let duration = range.duration.seconds
        let end = start + duration
        guard start.isFinite,
              start >= 0,
              duration.isFinite,
              duration > 0,
              end.isFinite,
              end >= start else {
            return nil
        }
        return (start, end)
    }
    .sorted { $0.start < $1.start }

    guard !ranges.isEmpty else {
        return loadedTimeRanges.isEmpty ? .empty : .unknown
    }
    guard var active = ranges.first(where: {
        currentTime >= $0.start - 0.25 && currentTime <= $0.end + 0.25
    }) else {
        return .empty
    }

    // ponytail: Merge only sub-250ms range gaps; expose discontinuities if
    // calibration shows this AVFoundation boundary tolerance is too generous.
    for range in ranges where range.start > active.start {
        guard range.start <= active.end + 0.25 else { break }
        active.end = max(active.end, range.end)
    }

    return PlaybackDiagnosticsBufferState(
        bufferedUntil: active.end,
        headroom: max(active.end - currentTime, 0)
    )
}

private struct PlaybackDiagnosticsItemContext {
    let sessionID: UUID
    let startedAt: Date
    let assetIdentifier: String?
}

struct PlaybackDiagnosticsLogCacheSnapshot: Equatable, Sendable {
    let network: PlaybackDiagnosticsSnapshot.Network
    let playbackType: String?
    let errorLogEventCount: Int
    let recentErrors: [PlaybackDiagnosticsError]

    static let empty = Self(
        network: .aggregatingAccessLogPeriods([]),
        playbackType: nil,
        errorLogEventCount: 0,
        recentErrors: []
    )

    static func capture(from item: AVPlayerItem) -> Self {
        let accessEvents = item.accessLog()?.events ?? []
        let network = PlaybackDiagnosticsSnapshot.Network.aggregatingAccessLogPeriods(
            accessEvents.map { event in
                PlaybackDiagnosticsSnapshot.Network(
                    accessLogEventCount: 1,
                    mediaRequestCount: nonnegative(event.numberOfMediaRequests),
                    numberOfStalls: nonnegative(event.numberOfStalls),
                    droppedVideoFrameCount: nonnegative(event.numberOfDroppedVideoFrames),
                    overdueDownloadCount: nonnegative(event.downloadOverdue),
                    bytesTransferred: nonnegative(event.numberOfBytesTransferred),
                    transferDuration: nonnegative(event.transferDuration),
                    observedBitRate: positive(event.observedBitrate),
                    indicatedBitRate: positive(event.indicatedBitrate),
                    indicatedAverageBitRate: positive(event.indicatedAverageBitrate),
                    averageVideoBitRate: positive(event.averageVideoBitrate),
                    averageAudioBitRate: positive(event.averageAudioBitrate),
                    observedBitRateStandardDeviation: nonnegative(
                        event.observedBitrateStandardDeviation
                    ),
                    switchBitRate: positive(event.switchBitrate),
                    segmentsDownloadedDuration: nonnegative(event.segmentsDownloadedDuration),
                    durationWatched: nonnegative(event.durationWatched),
                    startupTime: nonnegative(event.startupTime),
                    serverAddressChangeCount: nonnegative(event.numberOfServerAddressChanges)
                )
            }
        )
        let errorEvents = item.errorLog()?.events ?? []

        return Self(
            network: network,
            playbackType: sanitizedPlaybackType(accessEvents.last?.playbackType),
            errorLogEventCount: errorEvents.count,
            recentErrors: errorEvents.suffix(20).map {
                PlaybackDiagnosticsError(
                    occurredAt: $0.date,
                    domain: sanitizedPlaybackHealthErrorDomain($0.errorDomain),
                    code: $0.errorStatusCode
                )
            }
        )
    }

    private static func positive(_ value: Double) -> Double? {
        value.isFinite && value > 0 ? value : nil
    }

    private static func nonnegative(_ value: Double) -> Double? {
        value.isFinite && value >= 0 ? value : nil
    }

    private static func nonnegative(_ value: Int) -> Int? {
        value >= 0 ? value : nil
    }

    private static func nonnegative(_ value: Int64) -> Int64? {
        value >= 0 ? value : nil
    }

    private static func sanitizedPlaybackType(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.uppercased()
        return ["LIVE", "VOD", "FILE"].contains(normalized) ? normalized : nil
    }
}

final class PlaybackDiagnosticsLogCache: @unchecked Sendable {
    struct Token: Equatable, Sendable {
        let generation: UInt64
        let itemIdentifier: ObjectIdentifier
    }

    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var itemIdentifier: ObjectIdentifier?
    private var value: PlaybackDiagnosticsLogCacheSnapshot = .empty

    func begin(for item: AnyObject) -> Token {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        let identifier = ObjectIdentifier(item)
        itemIdentifier = identifier
        value = .empty
        return Token(generation: generation, itemIdentifier: identifier)
    }

    func invalidate() {
        lock.lock()
        generation &+= 1
        itemIdentifier = nil
        value = .empty
        lock.unlock()
    }

    @discardableResult
    func commit(
        _ newValue: PlaybackDiagnosticsLogCacheSnapshot,
        token: Token
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard generation == token.generation,
              itemIdentifier == token.itemIdentifier else {
            return false
        }
        value = newValue
        return true
    }

    func snapshot(for item: AnyObject) -> PlaybackDiagnosticsLogCacheSnapshot {
        lock.lock()
        defer { lock.unlock() }
        guard itemIdentifier == ObjectIdentifier(item) else { return .empty }
        return value
    }
}

private struct PlaybackHealthFallbackSeekContext {
    let monitor: MacOSPlaybackHealthMonitor
    let sessionID: UUID
    let item: AVPlayerItem
    let didSeekInBuffer: Bool?
}
#endif

public class AVPlayerWrapper: NSObject, PlayerProtocol {
    private var player: SmoothPlayer?
    private var playerView = AVPlayerView()
    private var currentSourceURL: URL?
    private var pipController: AVPictureInPictureController?
    
    private var playerItemStatusObserver: NSKeyValueObservation?
    private var playbackEndedObserver: Any?
    private var playbackFailedObserver: Any?
    private var playbackStalledObserver: Any?
    private var timeObserverToken: Any?
    private weak var timeObserverPlayer: AVPlayer?
    private var timeControlStatusObserver: NSKeyValueObservation?
    private var shouldEmitRuntimeState = false
    /// Survives pause/resume and item replacement, unlike `AVPlayer.rate`.
    private var desiredPlaybackRate: Float = 1.0

    /// Whether AVPlayer may route video to an external destination (AirPlay).
    ///
    /// Defaults to `false` to preserve the capture-protection posture this
    /// wrapper was built with. It is settable rather than hard-coded so the
    /// AirPlay affordance in the UI and the player's actual capability cannot
    /// disagree — previously the route picker was presented while external
    /// playback was unconditionally disabled, so choosing a device did nothing
    /// for video.
    var allowsExternalPlayback: Bool = false {
        didSet {
            guard let player else { return }
            applyExternalPlaybackPolicy(to: player)
        }
    }

    #if os(macOS)
    private var playbackHealthMonitor: MacOSPlaybackHealthMonitor?
    private let playbackDiagnosticsLogQueue = DispatchQueue(
        label: "com.netco.PlayerKit.playback-diagnostics-logs",
        qos: .utility
    )
    private let playbackDiagnosticsLogCache = PlaybackDiagnosticsLogCache()
    private var playbackDiagnosticsAccessLogObserver: NSObjectProtocol?
    private var playbackDiagnosticsErrorLogObserver: NSObjectProtocol?
    private var playbackDiagnosticsItemContext: PlaybackDiagnosticsItemContext?
    private var playbackDiagnosticsAudioTracks: [PlaybackDiagnosticsTrack] = []
    private var playbackDiagnosticsSubtitleTracks: [PlaybackDiagnosticsTrack] = []
    var onPlaybackHealthEvent: ((PlaybackHealthEvent) -> Void)?

    var activePlaybackHealthSessionID: UUID? {
        playbackHealthMonitor?.healthSessionID
    }

    var activePlaybackHealthAssetIdentifier: String? {
        playbackHealthMonitor?.assetIdentifier
    }
    #endif
    
    weak var lifecycleReporter: PlayerLifecycleReporting?
    var onRuntimeStateChange: ((PlayerRuntimeState) -> Void)?
    
    // MARK: - Initializer
    public override init() {
        super.init()
    }
    
    deinit {
        PlayerKitLog.debug("AVPlayerWrapper", "deinit")
        invalidateInstalledItemObservation()
        #if os(macOS)
        stopPlaybackHealthMonitoring()
        playbackDiagnosticsItemContext = nil
        #endif
        removeRuntimeTimeObserver()
        timeControlStatusObserver = nil
        let activePlayer = player
        // Fail any coalesced seeks so their callers are not left waiting on a
        // completion that can never arrive.
        activePlayer?.cancelCoalescedSeeks()
        activePlayer?.pause()
        playerView.player = nil
        activePlayer?.replaceCurrentItem(with: nil)
        player = nil
    }
}

// MARK: - PlaybackControlProtocol
extension AVPlayerWrapper: PlaybackControlProtocol {
    public var isPlaying: Bool {
        return player?.timeControlStatus == .playing
    }
    
    /// The user's selected rate, held separately from `AVPlayer.rate`.
    ///
    /// `AVPlayer.rate` is 0 while paused, so reading the speed back from it
    /// meant the selection was silently discarded on every pause and reset to
    /// 1× on the next `play()`.
    public var playbackSpeed: Float {
        get { desiredPlaybackRate }
        set {
            let sanitized = (newValue.isFinite && newValue > 0) ? newValue : 1.0
            desiredPlaybackRate = sanitized
            // Only push the rate down while already playing: assigning a
            // non-zero rate to a paused player would resume playback as a
            // side effect of changing the speed setting.
            if let player, player.timeControlStatus != .paused {
                player.rate = sanitized
            }
        }
    }

    public func play() {
        guard let player else { return }
        let targetRate = desiredPlaybackRate
        debugLog(
            "Play requested itemStatus=\(player.currentItem?.status.rawValue ?? -1) " +
            "timeControl=\(timeControlStatusLabel(player.timeControlStatus)) rate=\(player.rate)"
        )
        // Assign `rate` rather than calling playImmediately(atRate:). The load
        // path documents that automaticallyWaitsToMinimizeStalling must stay
        // enabled so HLS underruns produce a clean rebuffer instead of audible
        // crackle — but playImmediately(atRate:) is specified to force that
        // flag to false, which silently undid it on every play.
        player.rate = targetRate
        emitRuntimeState()
    }
    
    public func pause() {
        if let player {
            debugLog(
                "Pause requested timeControl=\(timeControlStatusLabel(player.timeControlStatus)) " +
                "rate=\(player.rate)"
            )
        }
        player?.pause()
        emitRuntimeState()
    }
    
    public func stop() {
        invalidateInstalledItemObservation()
        #if os(macOS)
        stopPlaybackHealthMonitoring()
        playbackDiagnosticsItemContext = nil
        #endif
        removeRuntimeTimeObserver()
        timeControlStatusObserver = nil
        let activePlayer = player
        // Fail any coalesced seeks so their callers are not left waiting on a
        // completion that can never arrive.
        activePlayer?.cancelCoalescedSeeks()
        activePlayer?.pause()
        playerView.player = nil
        activePlayer?.replaceCurrentItem(with: nil)
        currentSourceURL = nil
        player = nil
        emitRuntimeState()
    }

    public func setMuted(_ muted: Bool) {
        player?.isMuted = muted
    }
}

// MARK: - TimeControlProtocol
extension AVPlayerWrapper: TimeControlProtocol {
    public var currentTime: Double {
        return player?.currentTime().seconds ?? 0
    }
    
    public var duration: Double {
        guard let duration = player?.currentItem?.duration.seconds, duration.isFinite else { return 0 }
        return duration
    }
    
    public var bufferedDuration: Double {
        guard let timeRange = player?.currentItem?.loadedTimeRanges.first?.timeRangeValue else { return 0 }
        return CMTimeGetSeconds(timeRange.start) + CMTimeGetSeconds(timeRange.duration)
    }
    
    public var isBuffering: Bool {
        return player?.timeControlStatus == .waitingToPlayAtSpecifiedRate
    }
    
    public func seek(to time: Double, completion: ((Bool) -> Void)? = nil) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        #if os(macOS)
        let playbackHealthSeek = beginFallbackPlaybackHealthSeek(to: time)
        #endif
        debugLog(
            "Seek requested target=\(debugInterval(time)) current=\(debugInterval(currentTime)) " +
            "isPlaying=\(isPlaying) buffering=\(isBuffering)"
        )
        player?.seek(to: cmTime, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity) { [weak self] finished in
            self?.debugLog(
                "Seek completed finished=\(finished) target=\(self?.debugInterval(time) ?? "nan") " +
                "current=\(self?.debugInterval(self?.currentTime ?? .nan) ?? "nan") " +
                "isPlaying=\(self?.isPlaying ?? false) buffering=\(self?.isBuffering ?? false)"
            )
            #if os(macOS)
            self?.completeFallbackPlaybackHealthSeek(playbackHealthSeek)
            #endif
            completion?(finished)
            self?.emitRuntimeState()
        }
    }

    func seekExactly(to time: Double, completion: ((Bool) -> Void)? = nil) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.currentItem?.cancelPendingSeeks()
        #if os(macOS)
        let playbackHealthSeek = beginFallbackPlaybackHealthSeek(to: time)
        #endif
        debugLog(
            "Precise seek requested target=\(debugInterval(time)) current=\(debugInterval(currentTime)) " +
            "isPlaying=\(isPlaying) buffering=\(isBuffering)"
        )
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            self?.debugLog(
                "Precise seek completed finished=\(finished) target=\(self?.debugInterval(time) ?? "nan") " +
                "current=\(self?.debugInterval(self?.currentTime ?? .nan) ?? "nan") " +
                "isPlaying=\(self?.isPlaying ?? false) buffering=\(self?.isBuffering ?? false)"
            )
            #if os(macOS)
            self?.completeFallbackPlaybackHealthSeek(playbackHealthSeek)
            #endif
            completion?(finished)
            self?.emitRuntimeState()
        }
    }
    
    public func scrubForward(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    public func scrubBackward(by seconds: TimeInterval) {
        seek(to: currentTime - seconds)
    }
}

// MARK: - TrackSelectionProtocol
extension AVPlayerWrapper: TrackSelectionProtocol {
    public var availableAudioTracks: [TrackInfo] {
        guard let asset = player?.currentItem?.asset,
              let audioGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return [] }
        return audioGroup.options.map(trackInfo(for:))
    }
    
    public var availableSubtitles: [TrackInfo] {
        guard let asset = player?.currentItem?.asset,
              let subtitleGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return [] }
        return subtitleGroup.options.map(trackInfo(for:))
    }
    
    public var currentAudioTrack: TrackInfo? {
        guard let currentItem = player?.currentItem,
              let audioGroup = currentItem.asset.mediaSelectionGroup(forMediaCharacteristic: .audible),
              let selectedOption = currentItem.currentMediaSelection.selectedMediaOption(in: audioGroup) else { return nil }
        return trackInfo(for: selectedOption)
    }
    
    public var currentSubtitleTrack: TrackInfo? {
        guard let currentItem = player?.currentItem,
              let subtitleGroup = currentItem.asset.mediaSelectionGroup(forMediaCharacteristic: .legible),
              let selectedOption = currentItem.currentMediaSelection.selectedMediaOption(in: subtitleGroup) else { return nil }
        return trackInfo(for: selectedOption)
    }
    
    public func selectAudioTrack(withID id: String) {
        guard let asset = player?.currentItem?.asset,
              let audioGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .audible),
              let option = mediaSelectionOption(in: audioGroup, matching: id) else {
            debugLog("Audio track selection failed. requested_id_present=\(!id.isEmpty)")
            return
        }
        player?.currentItem?.select(option, in: audioGroup)
        #if os(macOS)
        if let item = player?.currentItem {
            refreshPlaybackDiagnosticsTrackCache(for: item)
        }
        #endif
    }
    
    public func selectSubtitle(withID id: String?) {
        guard let asset = player?.currentItem?.asset,
              let subtitleGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return }
        if let id = id,
           let option = mediaSelectionOption(in: subtitleGroup, matching: id) {
            player?.currentItem?.select(option, in: subtitleGroup)
        } else {
            player?.currentItem?.select(nil, in: subtitleGroup)
        }
        #if os(macOS)
        if let item = player?.currentItem {
            refreshPlaybackDiagnosticsTrackCache(for: item)
        }
        #endif
    }
}

// MARK: - MediaLoadingProtocol
extension AVPlayerWrapper: MediaLoadingProtocol {
    public func load(url: URL, lastPosition: Double? = nil) {
        #if os(macOS)
        load(
            url: url,
            lastPosition: lastPosition,
            playbackHealthAssetIdentifier: nil,
            playbackHealthMonitoringEnabled: false,
            playbackHealthMonitoringEligible: false
        )
        #else
        install(
            playerItem: AVPlayerItem(url: url),
            sourceURL: url,
            lastPosition: lastPosition
        )
        #endif
    }

    #if os(macOS)
    func load(
        url: URL,
        lastPosition: Double? = nil,
        playbackHealthAssetIdentifier: String?,
        playbackHealthMonitoringEnabled: Bool,
        playbackHealthMonitoringEligible: Bool = false
    ) {
        stopPlaybackHealthMonitoring()
        let playerItem = AVPlayerItem(url: url)

        let normalizedPlaybackHealthAssetIdentifier = playbackHealthAssetIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Normalize at the trust boundary so public events and retained samples
        // never carry a caller-provided URL, token, or other opaque raw value.
        let healthAssetIdentifier = diagnosticsIdentifier(
            normalizedPlaybackHealthAssetIdentifier.flatMap {
                $0.isEmpty ? nil : $0
            } ?? url.absoluteString
        )
        let diagnosticsContext = PlaybackDiagnosticsItemContext(
            sessionID: UUID(),
            startedAt: Date(),
            assetIdentifier: healthAssetIdentifier
        )
        playbackDiagnosticsItemContext = diagnosticsContext
        if playbackHealthMonitoringEnabled,
           playbackHealthMonitoringEligible,
           !url.isFileURL {
            let selectedAudioTrackProvider:
                @MainActor @Sendable () async -> PlaybackHealthAudioTrack? = {
                    [weak self, weak playerItem] in
                    guard let self, let playerItem else { return nil }
                    return await self.playbackHealthAudioTrack(for: playerItem)
                }
            let monitor = MacOSPlaybackHealthMonitor(
                item: playerItem,
                healthSessionID: diagnosticsContext.sessionID,
                assetIdentifier: healthAssetIdentifier,
                selectedAudioTrackProvider: selectedAudioTrackProvider,
                eventHandler: { [weak self] event in
                    guard self?.playbackHealthMonitor?.healthSessionID == event.healthSessionID else {
                        return
                    }
                    self?.onPlaybackHealthEvent?(event)
                }
            )
            playbackHealthMonitor = monitor
        }

        install(
            playerItem: playerItem,
            sourceURL: url,
            lastPosition: lastPosition
        )
    }
    #endif

    private func install(
        playerItem: AVPlayerItem,
        sourceURL: URL,
        lastPosition: Double?
    ) {
        invalidateInstalledItemObservation()
        currentSourceURL = sourceURL
        debugLog("Loading AVPlayer item. resume=\(lastPosition?.description ?? "nil")")
        // Automatic stall-waiting must stay enabled: with it disabled AVPlayer
        // renders straight through HLS buffer underruns, which is audible as
        // crackle/stutter instead of a clean rebuffer. Fast startup is
        // preserved by play() calling playImmediately(atRate:) once the item
        // is ready.
        if let player = player {
            configureContentProtection(for: player)
            player.automaticallyWaitsToMinimizeStalling = true
            player.replaceCurrentItem(with: playerItem)
            debugLog("Reusing existing AVPlayer instance for new item.")
        } else {
            player = SmoothPlayer(playerItem: playerItem)
            playerView.player = player
            if let player {
                configureContentProtection(for: player)
            }
            player?.automaticallyWaitsToMinimizeStalling = true
            debugLog("Created SmoothPlayer backing instance.")
        }
        configureRuntimeStateObserverIfNeeded()
        configureTimeControlStatusObserverIfNeeded()
        #if os(macOS)
        startPlaybackDiagnosticsLogObservation(for: playerItem)
        let callbackHealthMonitor = playbackHealthMonitor
        let callbackHealthSessionID = callbackHealthMonitor?.healthSessionID
        #endif
        
        // Observe the player item's status
        playerItemStatusObserver = playerItem.observe(
            \.status,
            options: [.initial, .new]
        ) { [weak self, weak playerItem] item, _ in
            guard item === playerItem else { return }
            DispatchQueue.main.async { [weak self, weak item] in
                guard let self, let item, self.player?.currentItem === item else { return }
                self.debugLog("Item status changed: \(item.status.rawValue)")
                if item.status == .readyToPlay {
                    // Tracks are now available; refresh track info.
                    if let asset = item.asset as? AVURLAsset {
                        asset.loadValuesAsynchronously(
                            forKeys: ["availableMediaCharacteristicsWithMediaSelectionOptions"]
                        ) { [weak self, weak item] in
                            DispatchQueue.main.async {
                                guard let self,
                                      let item,
                                      self.player?.currentItem === item else {
                                    return
                                }
                                self.ensureAudibleTrackSelectedIfNeeded(item: item)
                                #if os(macOS)
                                self.refreshPlaybackDiagnosticsTrackCache(for: item)
                                #endif
                                self.debugLog(
                                    "Item ready. tracks audio=\(self.availableAudioTracks.count) " +
                                    "subtitle=\(self.availableSubtitles.count)"
                                )
                                self.lifecycleReporter?.playerDidUpdateTracks()
                            }
                        }
                    }

                    self.lifecycleReporter?.playerDidBecomeReady()
                    self.emitRuntimeState()
                } else if item.status == .failed {
                    let description = item.error?.localizedDescription
                        ?? "Unknown AVPlayer item error"
                    #if os(macOS)
                    if let callbackHealthMonitor,
                       playbackHealthCallbackBelongsToCurrentSession(
                        capturedSessionID: callbackHealthSessionID,
                        currentSessionID: self.playbackHealthMonitor?.healthSessionID,
                        capturedItem: item,
                        currentItem: self.player?.currentItem
                       ),
                       self.playbackHealthMonitor === callbackHealthMonitor {
                        callbackHealthMonitor.recordTerminalPlaybackFailure(
                            error: item.error,
                            item: item
                        )
                    }
                    #endif
                    self.debugLog("Item failed. \(self.failureDiagnostics(for: item))")
                    self.lifecycleReporter?.playerDidFail(
                        with: .mediaLoadFailed(description)
                    )
                }
            }
        }
        
        // Observe when playback ends
        playbackEndedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.player?.currentItem === playerItem else { return }
            #if os(macOS)
            guard playbackHealthCallbackBelongsToCurrentSession(
                capturedSessionID: callbackHealthSessionID,
                currentSessionID: self.playbackHealthMonitor?.healthSessionID,
                capturedItem: playerItem,
                currentItem: self.player?.currentItem
            ), self.playbackHealthMonitor === callbackHealthMonitor else {
                return
            }
            callbackHealthMonitor?.recordNaturalPlaybackEnd(for: playerItem)
            #endif
            self.debugLog("Playback ended.")
            self.lifecycleReporter?.playerDidEndPlayback()
        }

        playbackFailedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] notification in
            guard let self, self.player?.currentItem === playerItem else { return }
            #if os(macOS)
            guard playbackHealthCallbackBelongsToCurrentSession(
                capturedSessionID: callbackHealthSessionID,
                currentSessionID: self.playbackHealthMonitor?.healthSessionID,
                capturedItem: playerItem,
                currentItem: self.player?.currentItem
            ), self.playbackHealthMonitor === callbackHealthMonitor else {
                return
            }
            #endif
            let underlyingError = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            #if os(macOS)
            callbackHealthMonitor?.recordTerminalPlaybackFailure(
                error: underlyingError,
                item: playerItem
            )
            #endif
            let nsError = underlyingError as NSError?
            self.debugLog(
                "Failed to play to end. domain=\(self.safeErrorDomain(nsError?.domain)) " +
                "code=\(nsError?.code ?? -1)"
            )
            self.lifecycleReporter?.playerDidFail(
                with: .mediaLoadFailed(underlyingError?.localizedDescription ?? "Unknown")
            )
        }

        playbackStalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.player?.currentItem === playerItem else { return }
            #if os(macOS)
            guard playbackHealthCallbackBelongsToCurrentSession(
                capturedSessionID: callbackHealthSessionID,
                currentSessionID: self.playbackHealthMonitor?.healthSessionID,
                capturedItem: playerItem,
                currentItem: self.player?.currentItem
            ), self.playbackHealthMonitor === callbackHealthMonitor else {
                return
            }
            callbackHealthMonitor?.recordPlaybackStall(for: playerItem)
            #endif
            self.debugLog("Playback stalled.")
            self.lifecycleReporter?.playerDidStall()
            self.emitRuntimeState()
        }
        
        // Seek to last position if provided, else start from the beginning
        if let position = lastPosition {
            let targetTime = CMTime(seconds: position, preferredTimescale: 600)
            debugLog("Applying initial seek to resume position \(debugInterval(position)).")
            player?.seek(to: targetTime)
        }
        
        debugLog("Calling play() immediately after load.")
        play()
    }
}

// MARK: - ViewRenderingProtocol
extension AVPlayerWrapper: ViewRenderingProtocol {
    public func getPlayerView() -> PKView {
        return playerView
    }
    
    /// Builds the Picture in Picture controller over the layer this wrapper
    /// already renders into.
    ///
    /// This previously assigned `nil`, which — combined with
    /// `isPictureInPictureSupported` returning a hard-coded `false` — meant the
    /// fully-implemented `AVPictureInPictureControllerDelegate` conformance
    /// below could never fire and `startPiP()` always bailed at its `guard let`.
    ///
    /// Note for hosts: PiP additionally requires the `audio` UIBackgroundMode
    /// and an active `.playback` audio session. Without those, AVKit reports
    /// failure through `failedToStartPictureInPictureWithError`.
    public func setupPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            pipController = nil
            return
        }

        let layer = playerView.playerLayer
        guard layer.player != nil else {
            debugLog("PiP setup deferred: no player is attached to the layer yet.")
            pipController = nil
            return
        }

        if let pipController, pipController.playerLayer === layer {
            return
        }

        guard let controller = AVPictureInPictureController(playerLayer: layer) else {
            debugLog("PiP setup failed: AVKit declined to build a controller for the layer.")
            pipController = nil
            return
        }
        controller.delegate = self
        pipController = controller
        debugLog("PiP controller configured.")
    }


    public func startPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            debugLog("PiP start ignored because the platform does not support Picture in Picture.")
            return
        }

        if pipController == nil {
            setupPiP()
        }

        guard let pipController else {
            debugLog("PiP start ignored because the controller is unavailable.")
            return
        }

        guard pipController.isPictureInPicturePossible || pipController.isPictureInPictureActive else {
            debugLog("PiP start ignored because Picture in Picture is not possible yet.")
            return
        }

        pipController.startPictureInPicture()
    }
    
    public func stopPiP() {
        pipController?.stopPictureInPicture()
    }
}

// MARK: - GestureHandlingProtocol
extension AVPlayerWrapper: GestureHandlingProtocol {
    public func handlePinchGesture(scale: CGFloat) {
        #if os(iOS)
        guard !UIDevice.current.isPortrait else { return }
        #endif
        scale > 1 ? setGravityToFill() : setGravityToDefault()
    }
    
    public func setGravityToDefault() {
        guard playerView.playerLayer.videoGravity != .resizeAspect else { return }
        playerView.playerLayer.videoGravity = .resizeAspect
    }
    
    public func setGravityToFill() {
        playerView.playerLayer.videoGravity = .resizeAspectFill
    }
}

extension AVPlayerWrapper: AVPictureInPictureControllerDelegate {
    public func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        lifecycleReporter?.playerDidChangePiPState(isActive: true)
    }
    
    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        lifecycleReporter?.playerDidChangePiPState(isActive: false)
    }
    
    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        let nsError = error as NSError
        debugLog(
            "PiP failed to start. domain=\(safeErrorDomain(nsError.domain)) code=\(nsError.code)"
        )
        lifecycleReporter?.playerDidChangePiPState(isActive: false)
    }

    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.setGravityToDefault()
            completionHandler(true)
        }
    }
}

extension AVPlayerWrapper: PlayerEventSource {}

extension AVPlayerWrapper: PlayerSeekWindowReporting {}

extension AVPlayerWrapper: PlayerPictureInPictureSupporting {
    var isPictureInPictureSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    var isPictureInPicturePossible: Bool {
        // Build the controller on demand so the capability can be reported
        // before anything has called startPiP().
        if pipController == nil {
            setupPiP()
        }
        return pipController?.isPictureInPicturePossible ?? false
    }
}

extension AVPlayerWrapper: PlayerStateSource {
    func startRuntimeStateUpdates() {
        shouldEmitRuntimeState = true
        configureRuntimeStateObserverIfNeeded()
        configureTimeControlStatusObserverIfNeeded()
        emitRuntimeState()
    }
    
    func stopRuntimeStateUpdates() {
        shouldEmitRuntimeState = false
        removeRuntimeTimeObserver()
        timeControlStatusObserver = nil
    }
}

// MARK: - StreamingInfoProtocol
extension AVPlayerWrapper: StreamingInfoProtocol {
    public func fetchStreamingInfo() -> StreamingInfo {
        guard let playerItem = player?.currentItem else {
            return StreamingInfo.placeholder
        }
        
        // Extract Buffer Duration as String
        let bufferDuration = formatBufferDuration(for: playerItem)
        
        // Extract Bitrate as String (if multiple bitrates are available, choose the first)
        let videoBitrate = extractVideoBitrate(from: playerItem)
        
        // Extract Resolution
        let resolution = extractResolution(from: playerItem)
        
        // Extract Frame Rate
        let frameRate = extractFrameRate(from: playerItem)
        
        return StreamingInfo(
            frameRate: frameRate,
            videoBitrate: videoBitrate,
            resolution: resolution,
            bufferDuration: bufferDuration
        )
    }
    
    // MARK: - Helper Methods
    private func formatBufferDuration(for playerItem: AVPlayerItem) -> String {
        guard let timeRange = playerItem.loadedTimeRanges.first?.timeRangeValue else {
            return "0 sec"
        }
        let duration = CMTimeGetSeconds(timeRange.duration)
        let intDuration = Int(duration.rounded())
        return "\(intDuration) sec"
    }
    
    private func extractVideoBitrate(from playerItem: AVPlayerItem) -> String {
        #if os(macOS)
        let indicatedBitRate = playbackDiagnosticsLogCache
            .snapshot(for: playerItem)
            .network
            .indicatedBitRate
        if let indicatedBitRate {
            return String(format: "%.2f Mbps", indicatedBitRate / 1_000_000)
        }
        #else
        let accessLogEvents = playerItem.accessLog()?.events ?? []
        // Choose the first indicated bitrate if available
        if let firstEvent = accessLogEvents.first {
            let mbps = firstEvent.indicatedBitrate / 1_000_000
            if mbps > 0 {
                return String(format: "%.2f Mbps", mbps)
            }
        }
        #endif
        return "0 Mbps"
    }
    
    private func extractResolution(from playerItem: AVPlayerItem) -> String {
        let size = playerItem.presentationSize
        return size.width > 0 && size.height > 0
        ? "\(Int(size.width))x\(Int(size.height))"
        : "Unknown"
    }
    
    private func extractFrameRate(from playerItem: AVPlayerItem) -> String {
        guard let videoTrack = playerItem.tracks.first?.currentVideoFrameRate else { return "Unknown" }
        return "\(Int(videoTrack)) fps"
    }
}

extension AVPlayerWrapper {
    #if os(macOS)
    func fetchPlaybackDiagnostics(
        monitoringEnabled: Bool,
        recentHealthEvents: [PlaybackHealthEvent],
        history: PlaybackDiagnosticsHistory = .empty,
        storyboard: PlaybackDiagnosticsStoryboard = .empty
    ) -> PlaybackDiagnosticsSnapshot {
        guard let player, let item = player.currentItem else {
            return .unavailable(.noPlayerItem)
        }

        let monitor = playbackHealthMonitor
        let monitorTelemetry = monitor?.telemetrySnapshot
        let diagnosticsContext = playbackDiagnosticsItemContext
        let capturedAt = Date()
        let availability: PlaybackDiagnosticsAvailability
        switch monitorTelemetry?.streamState {
        case .starting:
            availability = .startingAVMetrics
        case .observing:
            availability = .activeAVMetrics
        case .fallbackObserving:
            availability = .activeErrorLogFallback
        case .failed:
            availability = .failedAVMetrics
        case .ended:
            availability = .endedAVMetrics
        case nil where monitoringEnabled:
            availability = .monitorNotAttached
        case nil:
            availability = .monitoringDisabled
        }

        let currentTime = diagnosticsNonnegative(item.currentTime().seconds)
        let duration = diagnosticsPositive(item.duration.seconds)
        let buffer = playbackDiagnosticsBufferState(
            currentTime: currentTime,
            loadedTimeRanges: item.loadedTimeRanges.map(\.timeRangeValue)
        )
        let logSnapshot = playbackDiagnosticsLogCache.snapshot(for: item)
        let network = logSnapshot.network
        var errors = logSnapshot.recentErrors
        if let itemError = item.error as NSError? {
            errors.append(
                PlaybackDiagnosticsError(
                    occurredAt: nil,
                    domain: sanitizedPlaybackHealthErrorDomain(itemError.domain),
                    code: itemError.code
                )
            )
        }

        let presentationSize = item.presentationSize
        let maximumResolution = item.preferredMaximumResolution
        let playbackType = logSnapshot.playbackType
        let isLikelyHLS = currentSourceURL?.pathExtension.lowercased() == "m3u8"
            || (monitorTelemetry?.observedHLSRequestCount ?? 0) > 0
            ? true
            : nil
        let sessionEvents = recentHealthEvents.filter {
            guard let sessionID = diagnosticsContext?.sessionID else { return false }
            return $0.healthSessionID == sessionID
        }

        return PlaybackDiagnosticsSnapshot(
            session: PlaybackDiagnosticsSnapshot.Session(
                capturedAt: capturedAt,
                startedAt: diagnosticsContext?.startedAt,
                availability: availability,
                backend: "AVPlayer",
                monitorAttached: monitor != nil,
                sessionID: diagnosticsContext?.sessionID,
                assetIdentifier: diagnosticsContext?.assetIdentifier
            ),
            playback: PlaybackDiagnosticsSnapshot.Playback(
                itemStatus: diagnosticsItemStatus(item.status),
                timeControlStatus: timeControlStatusLabel(player.timeControlStatus),
                waitingReason: diagnosticsWaitingReason(player.reasonForWaitingToPlay),
                rate: sanitizedPlaybackDiagnosticsRate(Double(player.rate)),
                currentTime: currentTime,
                duration: duration,
                bufferedUntil: buffer.bufferedUntil,
                bufferHeadroom: buffer.headroom,
                loadedRangeCount: item.loadedTimeRanges.count,
                seekableRangeCount: item.seekableTimeRanges.count,
                isPlaybackLikelyToKeepUp: item.isPlaybackLikelyToKeepUp,
                isPlaybackBufferEmpty: item.isPlaybackBufferEmpty,
                isPlaybackBufferFull: item.isPlaybackBufferFull,
                automaticallyWaitsToMinimizeStalling: player.automaticallyWaitsToMinimizeStalling,
                isMuted: player.isMuted,
                volume: Double(player.volume),
                playbackType: playbackType,
                isLikelyHLS: isLikelyHLS,
                resolution: sanitizedPlaybackDiagnosticsResolution(
                    width: Double(presentationSize.width),
                    height: Double(presentationSize.height)
                ),
                frameRate: sanitizedPlaybackDiagnosticsFrameRate(item.tracks
                    .map(\.currentVideoFrameRate)
                    .first(where: { $0 > 0 })
                    .map(Double.init)),
                preferredForwardBufferDuration: item.preferredForwardBufferDuration,
                preferredPeakBitRate: item.preferredPeakBitRate,
                preferredMaximumResolution: sanitizedPlaybackDiagnosticsResolution(
                    width: Double(maximumResolution.width),
                    height: Double(maximumResolution.height)
                )
            ),
            network: network,
            audioTracks: playbackDiagnosticsAudioTracks,
            subtitleTracks: playbackDiagnosticsSubtitleTracks,
            errorLogEventCount: logSnapshot.errorLogEventCount,
            recentErrors: errors,
            recentHealthEvents: sessionEvents,
            monitor: monitorTelemetry,
            history: history,
            storyboard: storyboard
        )
    }

    private func diagnosticsItemStatus(_ status: AVPlayerItem.Status) -> String {
        switch status {
        case .unknown:
            return "unknown"
        case .readyToPlay:
            return "ready"
        case .failed:
            return "failed"
        @unknown default:
            return "unknown"
        }
    }

    private func diagnosticsWaitingReason(_ reason: AVPlayer.WaitingReason?) -> String? {
        guard let reason else { return nil }
        switch reason {
        case .evaluatingBufferingRate:
            return "Evaluating buffering rate"
        case .toMinimizeStalls:
            return "Waiting to minimize stalls"
        case .noItemToPlay:
            return "No item to play"
        default:
            return "Other AVFoundation waiting reason"
        }
    }

    private func diagnosticsIdentifier(_ identifier: String?) -> String? {
        guard let identifier, !identifier.isEmpty else {
            return nil
        }
        let bytes = identifier.utf8
        if bytes.allSatisfy({ (48...57).contains($0) }),
           let numericIdentifier = Int(identifier),
           numericIdentifier > 0 {
            return identifier
        }
        if identifier.utf8.count == 71,
           identifier.lowercased().hasPrefix("sha256:"),
           identifier.dropFirst(7).utf8.allSatisfy({
               (48...57).contains($0)
                   || (65...70).contains($0)
                   || (97...102).contains($0)
           }) {
            return identifier.lowercased()
        }

        // ponytail: cap adversarial metadata before hashing; raise the bound only
        // if real asset identifiers demonstrably exceed 4 KiB.
        guard bytes.count <= 4_096 else { return nil }
        let hashMaterial: Data
        if let components = URLComponents(string: identifier),
           let scheme = components.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            guard let host = components.host?.lowercased(), !host.isEmpty else {
                return nil
            }
            let port = components.port.map { ":\($0)" } ?? ""
            let path = components.percentEncodedPath.isEmpty
                ? "/"
                : components.percentEncodedPath
            hashMaterial = Data((host + port + path).utf8)
        } else {
            hashMaterial = Data(bytes)
        }
        let digest = SHA256.hash(data: hashMaterial)
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private func diagnosticsTrackIdentifier(_ identifier: String) -> String {
        let digest = SHA256.hash(data: Data(identifier.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private func diagnosticsPositive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private func diagnosticsNonnegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private func diagnosticsNonnegative(_ value: Int?) -> Int? {
        guard let value, value >= 0 else { return nil }
        return value
    }

    private func diagnosticsNonnegative(_ value: Int64?) -> Int64? {
        guard let value, value >= 0 else { return nil }
        return value
    }

    private func beginFallbackPlaybackHealthSeek(
        to targetTime: Double
    ) -> PlaybackHealthFallbackSeekContext? {
        if #available(macOS 15, *) {
            return nil
        }
        guard let item = player?.currentItem,
              let monitor = playbackHealthMonitor else {
            return nil
        }
        // ponytail: SmoothPlayer coalesces overlapping seeks and completes only
        // the newest request; revisit if the fallback player stops coalescing.
        if monitor.telemetrySnapshot.seeks.inProgressCount == 0 {
            monitor.recordSeekStarted(occurredAt: Date())
        }
        return PlaybackHealthFallbackSeekContext(
            monitor: monitor,
            sessionID: monitor.healthSessionID,
            item: item,
            didSeekInBuffer: playbackHealthTargetIsBuffered(targetTime, in: item)
        )
    }

    private func completeFallbackPlaybackHealthSeek(
        _ context: PlaybackHealthFallbackSeekContext?
    ) {
        guard let context else { return }
        let occurredAt = Date()
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  playbackHealthCallbackBelongsToCurrentSession(
                    capturedSessionID: context.sessionID,
                    currentSessionID: self.playbackHealthMonitor?.healthSessionID,
                    capturedItem: context.item,
                    currentItem: self.player?.currentItem
                  ),
                  self.playbackHealthMonitor === context.monitor else {
                return
            }
            context.monitor.recordSeekCompleted(
                didSeekInBuffer: context.didSeekInBuffer,
                occurredAt: occurredAt
            )
        }
    }

    private func playbackHealthTargetIsBuffered(
        _ targetTime: Double,
        in item: AVPlayerItem
    ) -> Bool? {
        guard targetTime.isFinite, targetTime >= 0 else { return nil }
        let validRanges = item.loadedTimeRanges.compactMap { value -> ClosedRange<Double>? in
            let range = value.timeRangeValue
            let start = range.start.seconds
            let duration = range.duration.seconds
            let end = start + duration
            guard start.isFinite,
                  duration.isFinite,
                  duration > 0,
                  end.isFinite else {
                return nil
            }
            return start ... end
        }
        return validRanges.contains { $0.contains(targetTime) }
    }

    private func stopPlaybackHealthMonitoring() {
        let monitor = playbackHealthMonitor
        playbackHealthMonitor = nil
        monitor?.stop()
    }

    @MainActor
    private func playbackHealthAudioTrack(
        for item: AVPlayerItem
    ) async -> PlaybackHealthAudioTrack? {
        guard let group = try? await item.asset.loadMediaSelectionGroup(
            for: .audible
        ),
              let option = item.currentMediaSelection.selectedMediaOption(in: group) else {
            return nil
        }

        let identifierDigest = SHA256.hash(data: Data(trackIdentifier(for: option).utf8))
        let identifier = "sha256:" + identifierDigest.map {
            String(format: "%02x", $0)
        }.joined()
        return PlaybackHealthAudioTrack(
            identifier: identifier,
            languageCode: sanitizedPlaybackHealthLanguage(
                option.extendedLanguageTag ?? option.locale?.identifier
            ),
            displayName: nil,
            isSelected: true
        )
    }

    func sanitizedPlaybackHealthLanguage(_ language: String?) -> String? {
        guard let language,
              !language.isEmpty,
              language.utf8.count <= 35,
              language.utf8.allSatisfy({ byte in
                  (65...90).contains(byte)
                      || (97...122).contains(byte)
                      || (48...57).contains(byte)
                      || byte == 45
                      || byte == 95
              }) else {
            return nil
        }

        let normalized = language.replacingOccurrences(of: "_", with: "-")
        let parts = normalized.split(separator: "-", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count),
              (2...3).contains(parts[0].count),
              parts[0].utf8.allSatisfy({
                  (65...90).contains($0) || (97...122).contains($0)
              }) else {
            return nil
        }

        var hasScript = false
        var hasRegion = false
        if parts.count >= 2 {
            hasScript = parts[1].count == 4
                && parts[1].utf8.allSatisfy({
                    (65...90).contains($0) || (97...122).contains($0)
                })
            hasRegion = (parts[1].count == 2
                && parts[1].utf8.allSatisfy({
                    (65...90).contains($0) || (97...122).contains($0)
                }))
                || (parts[1].count == 3
                    && parts[1].utf8.allSatisfy({ (48...57).contains($0) }))
            guard hasScript || hasRegion else { return nil }
        }
        if parts.count == 3 {
            guard hasScript,
                  (parts[2].count == 2
                      && parts[2].utf8.allSatisfy({
                          (65...90).contains($0) || (97...122).contains($0)
                      }))
                    || (parts[2].count == 3
                        && parts[2].utf8.allSatisfy({ (48...57).contains($0) }))
            else {
                return nil
            }
            hasRegion = true
        }

        let components = Locale.Components(identifier: normalized).languageComponents
        guard let languageCode = components.languageCode?.identifier.lowercased(),
              Locale(identifier: "en_US_POSIX")
                .localizedString(forLanguageCode: languageCode) != nil else {
            return nil
        }

        var canonical = [languageCode]
        if hasScript, let script = components.script?.identifier {
            canonical.append(script)
        }
        if hasRegion, let region = components.region?.identifier {
            canonical.append(region)
        }
        return canonical.joined(separator: "-")
    }

    private func sanitizedPlaybackHealthDisplayName(_ displayName: String) -> String? {
        var sanitized = ""
        for scalar in displayName.unicodeScalars
        where !CharacterSet.controlCharacters.contains(scalar)
            && sanitized.unicodeScalars.count < 80 {
            sanitized.unicodeScalars.append(scalar)
        }

        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    #endif

    private func applyExternalPlaybackPolicy(to player: AVPlayer) {
        player.allowsExternalPlayback = allowsExternalPlayback
        #if os(iOS)
        player.usesExternalPlaybackWhileExternalScreenIsActive = allowsExternalPlayback
        #endif
    }

    private func configureContentProtection(for player: AVPlayer) {
        applyExternalPlaybackPolicy(to: player)
        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, *) {
            player.audiovisualBackgroundPlaybackPolicy = .pauses
        }
    }

    var seekableTimeWindow: ClosedRange<Double>? {
        guard let ranges = player?.currentItem?.seekableTimeRanges,
              !ranges.isEmpty else {
            return nil
        }

        let windows = ranges.compactMap { range -> ClosedRange<Double>? in
            let timeRange = range.timeRangeValue
            let start = CMTimeGetSeconds(timeRange.start)
            let duration = CMTimeGetSeconds(timeRange.duration)
            guard start.isFinite, duration.isFinite else { return nil }
            let end = start + duration
            guard end > start else { return nil }
            return start ... end
        }

        guard let start = windows.map(\.lowerBound).min(),
              let end = windows.map(\.upperBound).max(),
              end > start else {
            return nil
        }

        return start ... end
    }

    var loadedTimeWindow: ClosedRange<Double>? {
        guard let ranges = player?.currentItem?.loadedTimeRanges,
              !ranges.isEmpty else {
            return nil
        }

        let windows = ranges.compactMap { range -> ClosedRange<Double>? in
            let timeRange = range.timeRangeValue
            let start = CMTimeGetSeconds(timeRange.start)
            let duration = CMTimeGetSeconds(timeRange.duration)
            guard start.isFinite, duration.isFinite else { return nil }
            let end = start + duration
            guard end > start else { return nil }
            return start ... end
        }

        guard let start = windows.map(\.lowerBound).min(),
              let end = windows.map(\.upperBound).max(),
              end > start else {
            return nil
        }

        return start ... end
    }

    func canSeekWithinCurrentWindow(
        to time: Double,
        tolerance: Double = 0.75
    ) -> Bool {
        let targetTime = max(time, 0)
        guard let window = seekableTimeWindow else { return false }
        return targetTime + tolerance >= window.lowerBound && targetTime <= window.upperBound + tolerance
    }

    func bufferedHeadroom(at time: Double? = nil) -> Double {
        guard let window = loadedTimeWindow else { return 0 }
        let referenceTime = max(time ?? currentTime, 0)
        return max(window.upperBound - referenceTime, 0)
    }

    private func trackInfo(for option: AVMediaSelectionOption) -> TrackInfo {
        TrackInfo(
            id: trackIdentifier(for: option),
            name: option.displayName,
            languageCode: option.extendedLanguageTag ?? option.locale?.languageCode
        )
    }

    private func trackIdentifier(for option: AVMediaSelectionOption) -> String {
        let propertyList = option.propertyList()
        if let data = try? PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .binary,
            options: 0
        ) {
            return "plist:\(data.base64EncodedString())"
        }

        return legacyTrackIdentifier(for: option)
    }

    private func mediaSelectionOption(
        in group: AVMediaSelectionGroup,
        matching id: String
    ) -> AVMediaSelectionOption? {
        if let propertyList = propertyListTrackIdentifier(id) {
            return group.mediaSelectionOption(withPropertyList: propertyList)
        }

        return group.options.first(where: { option in
            legacyTrackIdentifier(for: option) == id
                || option.extendedLanguageTag == id
                || option.locale?.identifier == id
                || option.displayName == id
        })
    }

    private func propertyListTrackIdentifier(_ id: String) -> Any? {
        guard id.hasPrefix("plist:") else { return nil }
        let encodedValue = String(id.dropFirst("plist:".count))
        guard let data = Data(base64Encoded: encodedValue) else { return nil }
        return try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
    }

    private func legacyTrackIdentifier(for option: AVMediaSelectionOption) -> String {
        option.extendedLanguageTag
            ?? option.locale?.identifier
            ?? option.displayName
    }

    private func emitRuntimeState() {
        guard shouldEmitRuntimeState else { return }
        let state = PlayerRuntimeState(
            isPlaying: isPlaying,
            isBuffering: isBuffering,
            currentTime: currentTime,
            duration: duration,
            bufferedDuration: bufferedDuration
        )
        onRuntimeStateChange?(state)
    }
    
    private func configureRuntimeStateObserverIfNeeded() {
        guard shouldEmitRuntimeState,
              let player = player,
              timeObserverToken == nil else { return }
        
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            self?.emitRuntimeState()
        }
        timeObserverPlayer = player
    }

    private func configureTimeControlStatusObserverIfNeeded() {
        #if os(macOS)
        let needsTimeControlObservation = shouldEmitRuntimeState || playbackHealthMonitor != nil
        #else
        let needsTimeControlObservation = shouldEmitRuntimeState
        #endif
        guard needsTimeControlObservation,
              let player,
              timeControlStatusObserver == nil else { return }

        timeControlStatusObserver = player.observe(
            \.timeControlStatus,
            options: [.initial, .new]
        ) { [weak self] observedPlayer, change in
            guard let self, let status = change.newValue else { return }
            let capturedItem = observedPlayer.currentItem
            let capturedMediaTime = observedPlayer.currentTime().seconds
            let capturedRate = observedPlayer.rate
            let capturedWaitingReasonLabel = waitingReasonLabel(
                observedPlayer.reasonForWaitingToPlay
            )
            #if os(macOS)
            let capturedWaitingReason = diagnosticsWaitingReason(
                observedPlayer.reasonForWaitingToPlay
            )
            let capturedHealthMonitor = playbackHealthMonitor
            let capturedHealthSessionID = capturedHealthMonitor?.healthSessionID
            let capturedAt = Date()
            let capturedSystemUptime = ProcessInfo.processInfo.systemUptime
            #endif

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.player === observedPlayer else { return }
                #if os(macOS)
                guard playbackHealthCallbackBelongsToCurrentSession(
                    capturedSessionID: capturedHealthSessionID,
                    currentSessionID: self.playbackHealthMonitor?.healthSessionID,
                    capturedItem: capturedItem,
                    currentItem: observedPlayer.currentItem
                ) else {
                    return
                }
                if let capturedHealthMonitor {
                    guard self.playbackHealthMonitor === capturedHealthMonitor else { return }
                }
                #else
                if let capturedItem {
                    guard observedPlayer.currentItem === capturedItem else { return }
                } else {
                    guard observedPlayer.currentItem == nil else { return }
                }
                #endif
                self.debugLog(
                    "timeControlStatus changed status=\(self.timeControlStatusLabel(status)) " +
                    "reason=\(capturedWaitingReasonLabel) rate=\(capturedRate) " +
                    "current=\(self.debugInterval(capturedMediaTime))"
                )
                #if os(macOS)
                capturedHealthMonitor?.recordTimeControlStatus(
                    status,
                    waitingReason: capturedWaitingReason,
                    mediaTime: capturedMediaTime,
                    occurredAt: capturedAt,
                    systemUptime: capturedSystemUptime
                )
                #endif
                self.emitRuntimeState()
            }
        }
    }
    
    private func removeRuntimeTimeObserver() {
        guard let timeObserverToken else { return }
        timeObserverPlayer?.removeTimeObserver(timeObserverToken)
        self.timeObserverToken = nil
        timeObserverPlayer = nil
    }

    private func invalidateInstalledItemObservation() {
        playerItemStatusObserver = nil
        removePlaybackEndedObserver()
        #if os(macOS)
        stopPlaybackDiagnosticsLogObservation()
        playbackDiagnosticsAudioTracks.removeAll(keepingCapacity: true)
        playbackDiagnosticsSubtitleTracks.removeAll(keepingCapacity: true)
        #endif
    }
    
    private func removePlaybackEndedObserver() {
        if let observer = playbackEndedObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackEndedObserver = nil
        }

        if let failedObserver = playbackFailedObserver {
            NotificationCenter.default.removeObserver(failedObserver)
            playbackFailedObserver = nil
        }

        if let stalledObserver = playbackStalledObserver {
            NotificationCenter.default.removeObserver(stalledObserver)
            playbackStalledObserver = nil
        }
    }

    #if os(macOS)
    private func startPlaybackDiagnosticsLogObservation(for item: AVPlayerItem) {
        stopPlaybackDiagnosticsLogObservation()
        let token = playbackDiagnosticsLogCache.begin(for: item)

        playbackDiagnosticsAccessLogObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.newAccessLogEntryNotification,
            object: item,
            queue: nil
        ) { [weak self, weak item] _ in
            guard let self, let item else { return }
            self.schedulePlaybackDiagnosticsLogRefresh(for: item, token: token)
        }

        playbackDiagnosticsErrorLogObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.newErrorLogEntryNotification,
            object: item,
            queue: nil
        ) { [weak self, weak item] _ in
            guard let self, let item else { return }
            self.schedulePlaybackDiagnosticsLogRefresh(for: item, token: token)
        }

        schedulePlaybackDiagnosticsLogRefresh(for: item, token: token)
    }

    private func schedulePlaybackDiagnosticsLogRefresh(
        for item: AVPlayerItem,
        token: PlaybackDiagnosticsLogCache.Token
    ) {
        let cache = playbackDiagnosticsLogCache
        playbackDiagnosticsLogQueue.async { [weak item] in
            guard let item else { return }
            let snapshot = PlaybackDiagnosticsLogCacheSnapshot.capture(from: item)
            cache.commit(snapshot, token: token)
        }
    }

    private func stopPlaybackDiagnosticsLogObservation() {
        if let observer = playbackDiagnosticsAccessLogObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackDiagnosticsAccessLogObserver = nil
        }
        if let observer = playbackDiagnosticsErrorLogObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackDiagnosticsErrorLogObserver = nil
        }
        playbackDiagnosticsLogCache.invalidate()
    }

    private func refreshPlaybackDiagnosticsTrackCache(for item: AVPlayerItem) {
        guard player?.currentItem === item else { return }
        let currentAudioID = currentAudioTrack?.id
        let currentSubtitleID = currentSubtitleTrack?.id
        playbackDiagnosticsAudioTracks = availableAudioTracks.map {
            PlaybackDiagnosticsTrack(
                identifier: diagnosticsTrackIdentifier($0.id),
                name: sanitizedPlaybackHealthDisplayName($0.name)
                    ?? "Unnamed audio track",
                languageCode: sanitizedPlaybackHealthLanguage($0.languageCode),
                isSelected: $0.id == currentAudioID
            )
        }
        playbackDiagnosticsSubtitleTracks = availableSubtitles.map {
            PlaybackDiagnosticsTrack(
                identifier: diagnosticsTrackIdentifier($0.id),
                name: sanitizedPlaybackHealthDisplayName($0.name)
                    ?? "Unnamed subtitle track",
                languageCode: sanitizedPlaybackHealthLanguage($0.languageCode),
                isSelected: $0.id == currentSubtitleID
            )
        }
    }
    #endif

    private func ensureAudibleTrackSelectedIfNeeded(item: AVPlayerItem) {
        guard let asset = item.asset as? AVURLAsset,
              let group = asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return }

        // If auto didn’t pick (common when all variants have DEFAULT=NO)
        if item.currentMediaSelection.selectedMediaOption(in: group) == nil {
            // Try device languages first: AVMediaSelectionGroup expects a Locale, not [String]
            var pick: AVMediaSelectionOption? = nil
            for languageCode in Locale.preferredLanguages {
                let locale = Locale(identifier: languageCode)
                let preferredOptions = AVMediaSelectionGroup.mediaSelectionOptions(from: group.options, with: locale)
                if let preferred = preferredOptions.first {
                    pick = preferred
                    break
                }
            }
            pick = pick
                ?? group.defaultOption
                ?? group.options.first(where: { $0.isPlayable })
                ?? group.options.first

            if let pick = pick {
                item.select(pick, in: group)
            } else if group.allowsEmptySelection, let first = group.options.first {
                // As a last resort, avoid silent playback on groups that allow empty selection
                item.select(first, in: group)
            }
        }

    }

    private func failureDiagnostics(for item: AVPlayerItem) -> String {
        let nsError = item.error as NSError?
        let code = nsError?.code ?? -1

        var errorLogSummary = "none"
        #if os(macOS)
        if let event = playbackDiagnosticsLogCache.snapshot(for: item).recentErrors.last {
            errorLogSummary =
                "errorDomain=\(event.domain ?? "unlisted") status=\(event.code)"
        }
        #else
        if let event = item.errorLog()?.events.last {
            errorLogSummary =
                "errorDomain=\(safeErrorDomain(event.errorDomain)) status=\(event.errorStatusCode)"
        }
        #endif

        return
            "domain=\(safeErrorDomain(nsError?.domain)) code=\(code) " +
            "errorLog=\(errorLogSummary)"
    }

    private func safeErrorDomain(_ domain: String?) -> String {
        #if os(macOS)
        return sanitizedPlaybackHealthErrorDomain(domain) ?? "unlisted"
        #else
        guard let domain,
              domain.utf8.count <= 80,
              domain.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0)
                      || $0 == "."
                      || $0 == "-"
                      || $0 == "_"
              }) else {
            return "unlisted"
        }
        return domain
        #endif
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        PlayerKitLog.debug("AVPlayerWrapper", message())
    }

    private func timeControlStatusLabel(_ status: AVPlayer.TimeControlStatus) -> String {
        switch status {
        case .paused:
            return "paused"
        case .waitingToPlayAtSpecifiedRate:
            return "waiting"
        case .playing:
            return "playing"
        @unknown default:
            return "unknown"
        }
    }

    private func waitingReasonLabel(_ reason: AVPlayer.WaitingReason?) -> String {
        guard let reason else { return "none" }
        return reason.rawValue
    }

    private func debugInterval(_ value: Double) -> String {
        guard value.isFinite else { return "nan" }
        return String(format: "%.3f", value)
    }
}
