import AVFoundation

public class AVPlayerWrapper: NSObject, PlayerProtocol {
    public var player: AVPlayer?

    public var isPlaying: Bool {
        return player?.timeControlStatus == .playing
    }

    public var currentTime: Double {
        return player?.currentTime().seconds ?? 0
    }

    public var duration: Double {
        guard let duration = player?.currentItem?.duration.seconds, duration.isFinite else { return 0 }
        return duration
    }

    public func play() {
        guard let player = player else { return }
        player.play()
    }

    public func pause() {
        guard let player = player else { return }
        player.pause()
    }

    public func stop() {
        guard let player = player else { return }
        player.pause()
        player.seek(to: .zero)
    }

    public func load(url: URL) {
        player = AVPlayer(url: url)
    }

    // MARK: - Audio and Subtitle Management

    public var availableAudioTracks: [String] {
        guard let asset = player?.currentItem?.asset else { return [] }
        // Retrieve the audio media selection group
        guard let audioGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return [] }
        
        // Extract the display names of available audio tracks
        return audioGroup.options.map { $0.displayName }
    }

    public var availableSubtitles: [String] {
        guard let asset = player?.currentItem?.asset else { return [] }
        // Retrieve the subtitle media selection group
        guard let subtitleGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return [] }
        
        // Extract the display names of available subtitle tracks
        return subtitleGroup.options.map { $0.displayName }
    }

    public func selectAudioTrack(index: Int) {
        guard let audioGroup = player?.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return }
        let audioOptions = audioGroup.options

        guard index < audioOptions.count else {
            print("Invalid audio track index")
            return
        }
        player?.currentItem?.select(audioOptions[index], in: audioGroup)
    }

    public func selectSubtitle(index: Int) {
        guard let subtitleGroup = player?.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return }
        let subtitleOptions = subtitleGroup.options

        guard index < subtitleOptions.count else {
            print("Invalid subtitle track index")
            return
        }
        player?.currentItem?.select(subtitleOptions[index], in: subtitleGroup)
    }
}

