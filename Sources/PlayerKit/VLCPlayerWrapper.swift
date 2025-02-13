import VLCKit

public class VLCPlayerWrapper: NSObject, PlayerProtocol {
    public var player: VLCMediaPlayer
    private let playerView = VLCPlayerView()
    public var pipController: VLCPictureInPictureWindowControlling?
    private var drawableProxy: VLCPlayerDrawableProxy?
    private var lastPosition: Double?
    
    public override init() {
        self.player = VLCMediaPlayer()
        super.init()
        
        drawableProxy = VLCPlayerDrawableProxy(wrapper: self)
        
        player.delegate = self
        player.drawable = drawableProxy
        
        setupObservers()
    }
    
    func setupLogging() {
        let logger = VLCConsoleLogger()
        logger.level = .debug
        logger.formatter.contextFlags = .levelContextModule
        player.libraryInstance.loggers = [logger]
    }
    
    func setupObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleDeviceLock), name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
    }
    
    @objc private func handleDeviceLock() {
        player.pause()
    }
    
    deinit {
        print("VLCPlayerWrapper deinit")
        NotificationCenter.default.removeObserver(self, name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
    }
    
}

// MARK: - PlaybackControlProtocol
extension VLCPlayerWrapper: PlaybackControlProtocol {
    public var isPlaying: Bool {
        return player.isPlaying
    }
    
    public var playbackSpeed: Float {
        get { return player.rate }
        set { player.rate = newValue }
    }
    
    public func play() {
        player.play()
    }
    
    public func pause() {
        player.pause()
    }
    
    public func stop() {
        player.stop()
    }
}

// MARK: - TimeControlProtocol
extension VLCPlayerWrapper: TimeControlProtocol {
    public var currentTime: Double {
        return Double(player.time.intValue) / 1000
    }
    
    public var duration: Double {
        return Double(player.media?.length.intValue ?? 0) / 1000
    }
    
    public var bufferedDuration: Double {
        return duration * Double(player.position)
    }
    
    public var isBuffering: Bool {
        return player.state == .buffering && !isPlaying
    }
    
    public func seek(to time: Double, completion: ((Bool) -> Void)? = nil) {
        guard duration > 0 else {
            completion?(false)
            return
        }
        
        let vlcTime = VLCTime(number: NSNumber(value: time * 1000))
        player.time = vlcTime
        
        completion?(true)
    }
    
    public func scrubForward(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }
    
    public func scrubBackward(by seconds: TimeInterval) {
        seek(to: currentTime - seconds)
    }
}

// MARK: - TrackSelectionProtocol
extension VLCPlayerWrapper: TrackSelectionProtocol {
    public var availableAudioTracks: [TrackInfo] {
        return player.audioTracks.compactMap { track in
            let id = track.trackName
            let name = track.trackName.split(separator: " ", maxSplits: 1).dropFirst().joined(separator: " ")
            let languageCode = track.language
            return TrackInfo(id: id, name: name, languageCode: languageCode)
        }
    }
    
    public var availableSubtitles: [TrackInfo] {
        return player.textTracks.compactMap { track in
            let id = track.trackName
            let name = track.trackName.split(separator: " ", maxSplits: 1).dropFirst().joined(separator: " ")
            let languageCode = track.language
            return TrackInfo(id: id, name: name, languageCode: languageCode)
        }
    }
    
    public var currentAudioTrack: TrackInfo? {
        guard let selectedTrack = player.audioTracks.first(where: { $0.isSelected }) else { return nil }
        let id = selectedTrack.trackName
        let name = selectedTrack.trackName.split(separator: " ", maxSplits: 1).dropFirst().joined(separator: " ")
        let languageCode = selectedTrack.language
        return TrackInfo(id: id, name: name, languageCode: languageCode)
    }
    
    public var currentSubtitleTrack: TrackInfo? {
        guard let selectedTrack = player.textTracks.first(where: { $0.isSelected }) else { return nil }
        let id = selectedTrack.trackName
        let name = selectedTrack.trackName.split(separator: " ", maxSplits: 1).dropFirst().joined(separator: " ")
        let languageCode = selectedTrack.language
        return TrackInfo(id: id, name: name, languageCode: languageCode)
    }
    
    public func selectAudioTrack(withID id: String) {
        if let track = player.audioTracks.first(where: { $0.trackName == id }) {
            track.isSelectedExclusively = true
        }
    }
    
    public func selectSubtitle(withID id: String?) {
        if let id = id, let track = player.textTracks.first(where: { $0.trackName == id }) {
            track.isSelectedExclusively = true
        } else {
            player.deselectAllTextTracks()
        }
    }
}

// MARK: - MediaLoadingProtocol
extension VLCPlayerWrapper: MediaLoadingProtocol {
    public func load(url: URL, lastPosition: Double? = nil) {
        let media = VLCMedia(url: url)
        self.lastPosition = lastPosition
        player.media = media
        player.media?.delegate = self
        player.play()
    }
}

// MARK: - VLCMediaDelegate
extension VLCPlayerWrapper: VLCMediaDelegate {
    public func mediaDidFinishParsing(_ aMedia: VLCMedia) {
        DispatchQueue.main.async { [weak self] in
            PlayerManager.shared.isMediaReady = true
        }
        if let position = lastPosition {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.player.time = VLCTime(number: NSNumber(value: position * 1000))
            }
        }
    }
    
    public func mediaMetaDataDidChange(_ aMedia: VLCMedia) {
        DispatchQueue.main.async {
            PlayerManager.shared.refreshTrackInfo()
        }
    }
}

// MARK: - VLCMediaPlayer Notification Handlers
extension VLCPlayerWrapper: VLCMediaPlayerDelegate {
    public func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        if newState == .stopped {
            DispatchQueue.main.async {
                PlayerManager.shared.videoDidEnd()
            }
        }
    }
    
    public func mediaPlayerTimeChanged(_ aNotification: Notification) {
    }
}


// MARK: - ViewRenderingProtocol
extension VLCPlayerWrapper: ViewRenderingProtocol {
    // Implement getPlayerView to return the cached UIView
    public func getPlayerView() -> UIView {
        return playerView
    }
    
    public func setupPiP() {}
    
    public func startPiP() {
        pipController?.startPictureInPicture()
    }
    
    public func stopPiP() {
        pipController?.stopPictureInPicture()
    }
}

// MARK: - GestureHandlingProtocol
extension VLCPlayerWrapper: GestureHandlingProtocol {
    public func handlePinchGesture(scale: CGFloat) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.player.videoAspectRatio = scale < 1 ? nil : self.currentAspectRatio()
        }
    }
    
    private func currentAspectRatio() -> String {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        return "\(Int(screenWidth)):\(Int(screenHeight))"
    }
}

// MARK: - StreamingInfoProtocol
extension VLCPlayerWrapper: StreamingInfoProtocol {
    public func fetchStreamingInfo() -> StreamingInfo {
        guard let media = player.media else {
            return .placeholder
        }
        
        let tracksInfo = media.tracksInformation as? [VLCMedia.Track] ?? []
        let resolution = extractCurrentResolution()
        let frameRate = extractFrameRate(from: tracksInfo)
        let videoBitrate = extractVideoBitrate(from: media)
        
        return StreamingInfo(
            frameRate: frameRate,
            videoBitrate: videoBitrate,
            resolution: resolution,
            bufferDuration: "0 sec"
        )
    }
    
    // MARK: - Helper Methods
    private func extractCurrentResolution() -> String {
        let videoSize = player.videoSize
        let width = Int(videoSize.width)
        let height = Int(videoSize.height)
        
        if width > 0 && height > 0 {
            return "\(width)x\(height)"
        }
        return "Unknown"
    }
    
    private func extractFrameRate(from tracks: [VLCMedia.Track]) -> String {
        for track in tracks {
            if track.type == .video, let videoTrack = track.video {
                let frameRate = videoTrack.frameRate
                let frameRateDenominator = videoTrack.frameRateDenominator
                if frameRate > 0, frameRateDenominator > 0 {
                    let fps = Double(frameRate) / Double(frameRateDenominator)
                    let roundedFps = Int(ceil(fps))
                    return "\(roundedFps) fps"
                }
            }
        }
        return "Unknown"
    }
    
    private func extractVideoBitrate(from media: VLCMedia) -> String {
        let bitrate = media.statistics.demuxBitrate
        let bitrateMbps = Double(bitrate)
        return String(format: "%.2f Mbps", bitrateMbps)
    }
    
}

