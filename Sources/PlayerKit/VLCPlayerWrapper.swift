import VLCKit

public class VLCPlayerWrapper: NSObject, PlayerProtocol {
    public var player: VLCMediaPlayer

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

    // PlayerProtocol property implementations
    public var isPlaying: Bool {
        return player.isPlaying
    }

    public var currentTime: Double {
        return Double(player.time.intValue) / 1000
    }

    public var duration: Double {
        return Double(player.media?.length.intValue ?? 0) / 1000
    }

    public var isBuffering: Bool {
        return player.state == .buffering
    }

    public var availableAudioTracks: [String] {
        guard let tracks = player.audioTracks as? [VLCMediaPlayer.Track] else { return [] }
        return tracks.map { $0.trackName ?? "Unknown" }
    }

    public var availableSubtitles: [String] {
        guard let tracks = player.textTracks as? [VLCMediaPlayer.Track] else { return [] }
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
        player.media = media
        player.play()
    }

    public func seek(to time: Double) {
        let position = Double(time / duration)
        player.position = position
    }

    public func selectAudioTrack(index: Int) {
        guard index < player.audioTracks.count else { return }
        player.audioTracks[index].isSelected = true
    }

    public func selectSubtitle(index: Int) {
        guard index < player.textTracks.count else { return }
        player.textTracks[index].isSelected = true
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
        DispatchQueue.main.async {
            PlayerManager.shared.updateTrackInfo(audioTracks: audioTracks, subtitles: subtitleTracks)
        }
    }
}

