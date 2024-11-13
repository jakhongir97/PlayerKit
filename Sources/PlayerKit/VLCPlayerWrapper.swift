import VLCKit

public class VLCPlayerWrapper: NSObject, PlayerProtocol {
    public var player: VLCMediaPlayer
    private var playerView: UIView?
    private var pipWindow: UIView?
    private var thumbnailGenerator: VLCPlayerThumbnailGenerator?

    public override init() {
        self.player = VLCMediaPlayer()
        super.init()

        // Register for VLC state and time change notifications
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(mediaPlayerStateChanged(_:)),
                                               name: VLCMediaPlayer.stateChangedNotification,
                                               object: player)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(mediaPlayerTimeChanged(_:)),
                                               name: VLCMediaPlayer.timeChangedNotification,
                                               object: player)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // Implement getPlayerView to return the cached UIView
    public func getPlayerView() -> UIView {
        if let existingView = playerView {
            return existingView
        }
        
        let newVlcView = UIView()
        DispatchQueue.main.async {
            self.player.drawable = newVlcView  // Set VLC's drawable to the view
        }
        playerView = newVlcView
        return newVlcView
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
        return player.state == .buffering
    }
    
    public func seek(to time: Double, completion: ((Bool) -> Void)? = nil) {
        let position = Double(time / duration)
        player.position = position
        completion?(true)  // Call the completion immediately since VLC does not have asynchronous seeking
    }
}

// MARK: - TrackSelectionProtocol
extension VLCPlayerWrapper: TrackSelectionProtocol {
    public var availableAudioTracks: [String] {
        guard let tracks = player.audioTracks as? [VLCMediaPlayer.Track] else { return [] }
        return tracks.map { $0.trackName }
    }

    public var availableSubtitles: [String] {
        guard let tracks = player.textTracks as? [VLCMediaPlayer.Track] else { return [] }
        return tracks.map { $0.trackName }
    }
    
    public var availableVideoTracks: [String] {
        guard let tracks = player.videoTracks as? [VLCMediaPlayer.Track] else { return [] }
        return tracks.map { $0.trackName }
    }
    
    public var currentAudioTrack: String? {
        guard let tracks = player.audioTracks as? [VLCMediaPlayer.Track] else { return nil }
        let selectedTrack = tracks.first(where: { $0.isSelected })
        return selectedTrack?.trackName
    }
    
    public var currentSubtitleTrack: String? {
        guard let tracks = player.textTracks as? [VLCMediaPlayer.Track] else { return nil }
        let selectedTrack = tracks.first(where: { $0.isSelected })
        return selectedTrack?.trackName
    }
    
    public var currentVideoTrack: String? {
        guard let tracks = player.videoTracks as? [VLCMediaPlayer.Track] else { return nil }
        let selectedTrack = tracks.first(where: { $0.isSelected })
        return selectedTrack?.trackName
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

    public func selectVideoTrack(index: Int) {
        guard index < player.videoTracks.count else { return }
        player.videoTracks[index].isSelected = true
    }
}

// MARK: - MediaLoadingProtocol
extension VLCPlayerWrapper: MediaLoadingProtocol {
    public func load(url: URL, lastPosition: Double? = nil) {
        let media = VLCMedia(url: url)
        media?.addOption(":network-caching=1000")
        player.media = media
        
        // Delay playback slightly to ensure drawable is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if self.player.drawable != nil {
                self.player.play()
                
                // Seek to last position if provided
                if let position = lastPosition {
                    self.player.time = VLCTime(number: NSNumber(value: position * 1000)) // VLCTime expects milliseconds
                }
            } else {
                print("Drawable is still nil after delay.")
            }
        }
    }
}

// MARK: - ViewRenderingProtocol
extension VLCPlayerWrapper: ViewRenderingProtocol {    
    public func setupPiP() {
        
    }
    
    public func startPiP() {
        
    }
    
    public func stopPiP() {
        
    }
}

// MARK: - ThumbnailGeneratorProtocol
extension VLCPlayerWrapper: ThumbnailGeneratorProtocol {
    public func generateThumbnail(at time: Double, completion: @escaping (UIImage?) -> Void) {
//        guard let media = player.media else {
//            completion(nil)
//            return
//        }
//        
//        if thumbnailGenerator == nil {
//            thumbnailGenerator = VLCPlayerThumbnailGenerator(media: media)
//        }
//        
//        thumbnailGenerator?.generateThumbnail(at: time, completion: completion)
    }
}

// MARK: - GestureHandlingProtocol
extension VLCPlayerWrapper: GestureHandlingProtocol {
    public func handlePinchGesture(scale: CGFloat) {
//        let screenWidth = UIScreen.main.bounds.width
//        let screenHeight = UIScreen.main.bounds.height
//
//        let aspectRatioString: String = scale > 1 ? {
//            let gcd = greatestCommonDivisor(Int(screenWidth), Int(screenHeight))
//            return "\(Int(screenWidth) / gcd):\(Int(screenHeight) / gcd)"
//        }() : ""
//
//        DispatchQueue.main.async { [weak self] in
//            self?.player.videoAspectRatio = aspectRatioString
//        }
//        print("New aspect ratio: \(aspectRatioString)")
    }

    private func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        return b == 0 ? a : greatestCommonDivisor(b, a % b)
    }
}

// MARK: - VLCMediaPlayer Notification Handlers
extension VLCPlayerWrapper {
    @objc private func mediaPlayerStateChanged(_ notification: Notification) {
        guard let player = notification.object as? VLCMediaPlayer else { return }
    }

    @objc private func mediaPlayerTimeChanged(_ notification: Notification) {
        guard let player = notification.object as? VLCMediaPlayer else { return }
    }
}

