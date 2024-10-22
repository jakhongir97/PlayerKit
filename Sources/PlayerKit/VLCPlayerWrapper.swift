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

    // PlayerProtocol property implementations
    public var isPlaying: Bool {
        return player.isPlaying
    }

    public var currentTime: Double {
        return Double(player.time.intValue) / 1000
    }
    
    public var bufferedDuration: Double {
        return duration * Double(player.position)
    }

    public var duration: Double {
        return Double(player.media?.length.intValue ?? 0) / 1000
    }

    public var isBuffering: Bool {
        return player.state == .buffering
    }
    
    public var playbackSpeed: Float {
        get {
            return player.rate ?? 1.0
        }
        set {
            player.rate = newValue
        }
    }

    public var availableAudioTracks: [String] {
        guard let tracks = player.audioTracks as? [VLCMediaPlayer.Track] else { return [] }
        return tracks.map { $0.trackName ?? "Unknown" }
    }

    public var availableSubtitles: [String] {
        guard let tracks = player.textTracks as? [VLCMediaPlayer.Track] else { return [] }
        return tracks.map { $0.trackName ?? "Unknown" }
    }
    
    public var availableVideoTracks: [String] {
        guard let tracks = player.videoTracks as? [VLCMediaPlayer.Track] else { return [] }
        return tracks.map { $0.trackName ?? "Unknown" }
    }

    // Implement PlayerProtocol methods
    public func play() {
        player.play()
    }

    public func pause() {
        player.pause()
    }

    public func stop() {
        player.stop()
    }

    public func load(url: URL) {
        let media = VLCMedia(url: url)
        media?.addOption(":network-caching=1000")
        player.media = media

        // Delay the playback slightly to ensure drawable is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if self.player.drawable != nil {
                print("Starting playback with drawable set.")
                self.player.play()
            } else {
                print("Drawable is still nil after delay.")
            }
        }
    }

    public func seek(to time: Double, completion: ((Bool) -> Void)? = nil) {
        let position = Double(time / duration)
        player.position = position
        completion?(true)  // Call the completion immediately since VLC does not have asynchronous seeking
    }

    public func selectAudioTrack(index: Int) {
        guard index < player.audioTracks.count else { return }
        player.audioTracks[index].isSelected = true
    }

    public func selectSubtitle(index: Int) {
        guard index < player.textTracks.count else { return }
        player.textTracks[index].isSelected = true
    }
    
    // Select video track
    public func selectVideoTrack(index: Int) {
        guard index < player.videoTracks.count else { return }
        player.videoTracks[index].isSelected = true
    }

    // Handle VLCMediaPlayerStateChangedNotification
    @objc private func mediaPlayerStateChanged(_ notification: Notification) {
        guard let player = notification.object as? VLCMediaPlayer else { return }
        if player.state == .playing || player.state == .buffering {
            refreshTrackInfo()
        }
    }

    // Handle VLCMediaPlayerTimeChangedNotification
    @objc private func mediaPlayerTimeChanged(_ notification: Notification) {
        guard let player = notification.object as? VLCMediaPlayer else { return }
        DispatchQueue.main.async {
            PlayerManager.shared.currentTime = Double(player.time.intValue) / 1000
        }
    }

    private func refreshTrackInfo() {
        let audioTracks = availableAudioTracks
        let subtitleTracks = availableSubtitles
        let videoTracks = availableVideoTracks
        DispatchQueue.main.async {
            PlayerManager.shared.updateTrackInfo(audioTracks: audioTracks, subtitles: subtitleTracks, videoTracks: videoTracks)
        }
    }
}

// MARK: - VLCPlayerWrapper Extension
extension VLCPlayerWrapper {
    public func generateThumbnail(at time: Double, completion: @escaping (UIImage?) -> Void) {
        guard let media = player.media else {
            completion(nil)
            return
        }
        
        // Reuse the same instance of VLCPlayerThumbnailGenerator
        if thumbnailGenerator == nil {
            thumbnailGenerator = VLCPlayerThumbnailGenerator(media: media)
        }
        
        thumbnailGenerator?.generateThumbnail(at: time, completion: completion)
    }
}

extension VLCPlayerWrapper {
    // Setup custom PiP (floating window)
    public func setupPiP() {
    }
    
    // Start custom PiP for VLCPlayer
    public func startPiP() {
    }
    
    // Stop custom PiP for VLCPlayer
    public func stopPiP() {
    }
}
