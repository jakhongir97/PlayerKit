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
    public var availableAudioTracks: [String] {
        return player.audioTracks.compactMap { track in
            track.trackName.split(separator: " ", maxSplits: 1).dropFirst().joined(separator: " ")
        }
    }

    public var availableSubtitles: [String] {
        return player.textTracks.compactMap { track in
            track.trackName.split(separator: " ", maxSplits: 1).dropFirst().joined(separator: " ")
        }
    }
    
    public var currentAudioTrack: String? {
        let selectedTrack = player.audioTracks.first(where: { $0.isSelected })
        return selectedTrack?.trackName.split(separator: " ", maxSplits: 1).dropFirst().joined(separator: " ")
    }
    
    public var currentSubtitleTrack: String? {
        let selectedTrack = player.textTracks.first(where: { $0.isSelected })
        return selectedTrack?.trackName.split(separator: " ", maxSplits: 1).dropFirst().joined(separator: " ")
    }
    
    public func selectAudioTrack(index: Int) {
        guard index < player.audioTracks.count else { return }
        player.audioTracks[index].isSelected = true
    }

    public func selectSubtitle(index: Int?) {
        if let index = index {
            guard index < player.textTracks.count else { return }
            player.textTracks[index].isSelected = true
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
        DispatchQueue.main.async {
            PlayerManager.shared.refreshTrackInfo()
        }
    }
}

// MARK: - GestureHandlingProtocol
extension VLCPlayerWrapper: GestureHandlingProtocol {
    public func handlePinchGesture(scale: CGFloat) {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height

        let aspectRatioString: String
        if scale > 1 {
            let gcd = greatestCommonDivisor(Int(screenWidth), Int(screenHeight))
            aspectRatioString = "\(Int(screenWidth) / gcd):\(Int(screenHeight) / gcd)"
        } else {
            aspectRatioString = ""
        }

        DispatchQueue.main.async { [weak self] in
            self?.player.videoAspectRatio = aspectRatioString
        }
        print("New aspect ratio: \(aspectRatioString)")
    }

    private func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        return b == 0 ? a : greatestCommonDivisor(b, a % b)
    }
}

// MARK: - VLCMediaPlayer Notification Handlers
extension VLCPlayerWrapper: VLCMediaPlayerDelegate {
    public func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
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

    public func seek(by offset: Int64) {
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
