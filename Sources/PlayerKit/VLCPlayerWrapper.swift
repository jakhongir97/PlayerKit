import VLCKit

public class VLCPlayerWrapper: NSObject, PlayerProtocol {
    public var player: VLCMediaPlayer
    private let playerView = VLCPlayerView()
    private weak var pipController: VLCPictureInPictureWindowControlling?

    public override init() {
        self.player = VLCMediaPlayer()
        super.init()

        player.delegate = self
        player.drawable = self
        
        setupObservers()
    }
    
    func setupObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleDeviceLock), name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
    }

    @objc private func handleDeviceLock() {
        player.pause()
    }

    deinit {
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
        let position = Float(time / duration)
        player.position = Double(position)
        completion?(true)
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
            track.isSelected = true
        }
    }
    
    public func selectSubtitle(withID id: String?) {
        if let id = id, let track = player.textTracks.first(where: { $0.trackName == id }) {
            track.isSelected = true
        } else {
            player.deselectAllTextTracks()
        }
    }
}

// MARK: - MediaLoadingProtocol
extension VLCPlayerWrapper: MediaLoadingProtocol {
    public func load(url: URL, lastPosition: Double? = nil) {
        let media = VLCMedia(url: url)
        player.media = media
        player.media?.delegate = self
        
        // Seek to last position if provided
        if let position = lastPosition {
            player.time = VLCTime(number: NSNumber(value: position * 1000)) // VLCTime expects milliseconds
        }
        player.play()
    }
}

// MARK: - VLCMediaDelegate
extension VLCPlayerWrapper: VLCMediaDelegate {
    public func mediaDidFinishParsing(_ aMedia: VLCMedia) {
        DispatchQueue.main.async { [weak self] in
            PlayerManager.shared.isMediaReady = true
        }
    }
    
    public func mediaMetaDataDidChange(_ aMedia: VLCMedia) {
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

// MARK: - VLCMediaPlayer Notification Handlers
extension VLCPlayerWrapper: VLCMediaPlayerDelegate {
    public func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        DispatchQueue.main.async {
            PlayerManager.shared.refreshTrackInfo()
        }
        switch newState {
        case .stopped:
            DispatchQueue.main.async {
                PlayerManager.shared.videoDidEnd()
            }
        default:
            break
        }
    }
    
    public func mediaPlayerTimeChanged(_ aNotification: Notification) {
    }
}

// MARK: - VLCPictureInPictureMediaControlling
extension VLCPlayerWrapper: VLCPictureInPictureMediaControlling {
    public func mediaTime() -> Int64 {
        return player.time.value?.int64Value ?? 0
    }
    
    public func mediaLength() -> Int64 {
        return player.media?.length.value?.int64Value ?? 0
    }

    public func seek(by offset: Int64) async {
        
    }
    
    public func isMediaSeekable() -> Bool {
        return player.isSeekable
    }

    public func isMediaPlaying() -> Bool {
        return player.isPlaying
    }
}

// MARK: - VLCPictureInPictureDrawable
extension VLCPlayerWrapper: VLCPictureInPictureDrawable {
    public func mediaController() -> (any VLCPictureInPictureMediaControlling)! {
        return self
    }
    
    public func pictureInPictureReady() -> (((any VLCPictureInPictureWindowControlling)?) -> Void)! {
        return { [weak self] controller in
            self?.pipController = controller
        }
    }
}

// MARK: - VLCDrawable
extension VLCPlayerWrapper: VLCDrawable {
    public func addSubview(_ view: UIView) {
        playerView.addSubview(view)
    }

    public func bounds() -> CGRect {
        return playerView.bounds
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

// MARK: - ThumbnailGeneratorProtocol
extension VLCPlayerWrapper: ThumbnailGeneratorProtocol {
    public func generateThumbnail(at time: Double, completion: @escaping (UIImage?) -> Void) {
        
    }
}
