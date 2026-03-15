import AVKit
#if canImport(UIKit)
import UIKit
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
    
    weak var lifecycleReporter: PlayerLifecycleReporting?
    var onRuntimeStateChange: ((PlayerRuntimeState) -> Void)?
    
    // MARK: - Initializer
    public override init() {
        super.init()
    }
    
    deinit {
        print("AvPlayerWrapper deinit")
        playerItemStatusObserver = nil
        removePlaybackEndedObserver()
        removeRuntimeTimeObserver()
        timeControlStatusObserver = nil
        let activePlayer = player
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
    
    public var playbackSpeed: Float {
        get { return player?.rate ?? 1.0 }
        set { player?.rate = newValue }
    }
    
    public func play() {
        guard let player else { return }
        let targetRate = playbackSpeed > 0 ? playbackSpeed : 1.0
        debugLog(
            "Play requested url=\(currentSourceURL?.debugDescription ?? "nil") " +
            "itemStatus=\(player.currentItem?.status.rawValue ?? -1) " +
            "timeControl=\(timeControlStatusLabel(player.timeControlStatus)) rate=\(player.rate)"
        )
        if player.currentItem?.status == .readyToPlay {
            player.playImmediately(atRate: targetRate)
        } else {
            player.play()
        }
        emitRuntimeState()
    }
    
    public func pause() {
        if let player {
            debugLog(
                "Pause requested url=\(currentSourceURL?.debugDescription ?? "nil") " +
                "timeControl=\(timeControlStatusLabel(player.timeControlStatus)) rate=\(player.rate)"
            )
        }
        player?.pause()
        emitRuntimeState()
    }
    
    public func stop() {
        playerItemStatusObserver = nil
        removePlaybackEndedObserver()
        removeRuntimeTimeObserver()
        timeControlStatusObserver = nil
        let activePlayer = player
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
            completion?(finished)
            self?.emitRuntimeState()
        }
    }

    func seekExactly(to time: Double, completion: ((Bool) -> Void)? = nil) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.currentItem?.cancelPendingSeeks()
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
            debugLog("Audio track selection failed. id=\(id)")
            return
        }
        player?.currentItem?.select(option, in: audioGroup)
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
    }
}

// MARK: - MediaLoadingProtocol
extension AVPlayerWrapper: MediaLoadingProtocol {
    public func load(url: URL, lastPosition: Double? = nil) {
        currentSourceURL = url
        debugLog("Loading AVPlayer item. url=\(url.debugDescription) resume=\(lastPosition?.description ?? "nil")")
        let playerItem = AVPlayerItem(url: url)
        if let player = player {
            player.automaticallyWaitsToMinimizeStalling = false
            player.replaceCurrentItem(with: playerItem)
            debugLog("Reusing existing AVPlayer instance for new item.")
        } else {
            player = SmoothPlayer(playerItem: playerItem)
            playerView.player = player
            setupPiP()
            player?.allowsExternalPlayback = true
            player?.automaticallyWaitsToMinimizeStalling = false
            debugLog("Created SmoothPlayer backing instance.")
        }
        configureRuntimeStateObserverIfNeeded()
        configureTimeControlStatusObserverIfNeeded()

        playerItemStatusObserver = nil
        removePlaybackEndedObserver()
        
        // Observe the player item's status
        playerItemStatusObserver = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self = self else { return }
            self.debugLog("Item status changed: \(item.status.rawValue) url=\(self.currentSourceURL?.debugDescription ?? "nil")")
            if item.status == .readyToPlay {
                // Tracks are now available; refresh track info
                if let asset = item.asset as? AVURLAsset {
                    asset.loadValuesAsynchronously(forKeys: ["availableMediaCharacteristicsWithMediaSelectionOptions"]) {
                        self.ensureAudibleTrackSelectedIfNeeded(item: item)
                        self.debugLog(
                            "Item ready. tracks audio=\(self.availableAudioTracks.count) " +
                            "subtitle=\(self.availableSubtitles.count)"
                        )
                        DispatchQueue.main.async {
                            self.lifecycleReporter?.playerDidUpdateTracks()
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self.lifecycleReporter?.playerDidBecomeReady()
                    self.emitRuntimeState()
                }
            } else if item.status == .failed {
                let description = item.error?.localizedDescription ?? "Unknown AVPlayer item error"
                self.debugLog("Item failed. \(self.failureDiagnostics(for: item))")
                DispatchQueue.main.async {
                    self.lifecycleReporter?.playerDidFail(with: .mediaLoadFailed(description))
                }
            }
        }
        
        // Observe when playback ends
        playbackEndedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.debugLog("Playback ended.")
            self?.lifecycleReporter?.playerDidEndPlayback()
        }

        playbackFailedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let underlyingError = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription ?? "Unknown"
            self.debugLog("Failed to play to end. url=\(self.currentSourceURL?.debugDescription ?? "nil") underlying=\(underlyingError)")
            self.lifecycleReporter?.playerDidFail(with: .mediaLoadFailed(underlyingError))
        }

        playbackStalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.debugLog("Playback stalled. url=\(self.currentSourceURL?.debugDescription ?? "nil")")
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
    
    public func setupPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            pipController = nil
            return
        }

        if pipController == nil {
            pipController = AVPictureInPictureController(playerLayer: playerView.playerLayer)
            pipController?.delegate = self
        }
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
        debugLog("PiP failed to start. error=\(error.localizedDescription)")
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

extension AVPlayerWrapper: PlayerMuteControlling, PlayerPreciseSeeking, PlayerSeekWindowReporting {}

extension AVPlayerWrapper: PlayerPictureInPictureSupporting {
    var isPictureInPictureSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    var isPictureInPicturePossible: Bool {
        pipController?.isPictureInPicturePossible ?? false
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
        let accessLogEvents = playerItem.accessLog()?.events ?? []
        // Choose the first indicated bitrate if available
        if let firstEvent = accessLogEvents.first {
            let mbps = firstEvent.indicatedBitrate / 1_000_000
            if mbps > 0 {
                return String(format: "%.2f Mbps", mbps)
            }
        }
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
        guard shouldEmitRuntimeState,
              let player,
              timeControlStatusObserver == nil else { return }

        timeControlStatusObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.debugLog(
                    "timeControlStatus changed status=\(self.timeControlStatusLabel(player.timeControlStatus)) " +
                    "reason=\(self.waitingReasonLabel(player.reasonForWaitingToPlay)) rate=\(player.rate) " +
                    "current=\(self.debugInterval(self.currentTime))"
                )
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
        let domain = nsError?.domain ?? "unknown"
        let code = nsError?.code ?? -1
        let reason = nsError?.localizedFailureReason ?? "none"
        let suggestion = nsError?.localizedRecoverySuggestion ?? "none"

        var errorLogSummary = "none"
        if let event = item.errorLog()?.events.last {
            errorLogSummary =
                "errorDomain=\(event.errorDomain) status=\(event.errorStatusCode) " +
                "comment=\(event.errorComment ?? "none") uri=\(event.uri ?? "none")"
        }

        return
            "url=\(currentSourceURL?.debugDescription ?? "nil") " +
            "domain=\(domain) code=\(code) reason=\(reason) suggestion=\(suggestion) " +
            "errorLog=\(errorLogSummary)"
    }

    private func debugLog(_ message: String) {
        print("[PlayerKit][AVPlayerWrapper] \(message)")
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
