import AVFoundation
import UIKit

public class AVPlayerWrapper: NSObject, PlayerProtocol {
    public var player: AVPlayer?
    
    // Lazy initialization to create the thumbnail generator only when it's first accessed
    private lazy var thumbnailGenerator: AVPlayerThumbnailGenerator? = {
        guard let asset = player?.currentItem?.asset else { return nil }
        return AVPlayerThumbnailGenerator(asset: asset)
    }()
    

    // PlayerProtocol property implementations
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

    public var isBuffering: Bool {
        return player?.timeControlStatus == .waitingToPlayAtSpecifiedRate
    }
    
    public var playbackSpeed: Float {
        get {
            return player?.rate ?? 1.0
        }
        set {
            player?.rate = newValue 
        }
    }

    // Audio and Subtitle track management
    public var availableAudioTracks: [String] {
        guard let asset = player?.currentItem?.asset else { return [] }
        guard let audioGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return [] }
        return audioGroup.options.map { $0.displayName }
    }

    public var availableSubtitles: [String] {
        guard let asset = player?.currentItem?.asset else { return [] }
        guard let subtitleGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return [] }
        return subtitleGroup.options.map { $0.displayName }
    }
    
    // Get available video tracks (example for HLS streams)
    public var availableVideoTracks: [String] {
        guard let asset = player?.currentItem?.asset else { return [] }
        guard let videoGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .visual) else { return [] }
        return videoGroup.options.map { $0.displayName } ?? []
    }

    // Implement PlayerProtocol methods
    public func play() {
        player?.play()
    }

    public func pause() {
        player?.pause()
    }

    public func stop() {
        player?.pause()
        player?.seek(to: .zero)
    }

    public func load(url: URL) {
        player = AVPlayer(url: url)
        refreshTrackInfo()
    }

    // Updated seek method with optional completion handler
    public func seek(to time: Double, completion: ((Bool) -> Void)? = nil) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            completion?(finished)  // Call completion when seeking finishes
        }
    }

    public func selectAudioTrack(index: Int) {
        guard let audioGroup = player?.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return }
        let audioOptions = audioGroup.options
        guard index < audioOptions.count else { return }
        player?.currentItem?.select(audioOptions[index], in: audioGroup)
    }

    public func selectSubtitle(index: Int) {
        guard let subtitleGroup = player?.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return }
        let subtitleOptions = subtitleGroup.options
        guard index < subtitleOptions.count else { return }
        player?.currentItem?.select(subtitleOptions[index], in: subtitleGroup)
    }
    
    // Select video track
    public func selectVideoTrack(index: Int) {
        guard let videoGroup = player?.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .visual) else { return }
        let videoOptions = videoGroup.options
        guard index < videoOptions.count else { return }
        player?.currentItem?.select(videoOptions[index], in: videoGroup)
    }

    // Refresh available audio and subtitle tracks
    private func refreshTrackInfo() {
        let audioTracks = availableAudioTracks
        let subtitleTracks = availableSubtitles
        let videoTracks = availableVideoTracks
        DispatchQueue.main.async {
            PlayerManager.shared.updateTrackInfo(audioTracks: audioTracks, subtitles: subtitleTracks, videoTracks: videoTracks)
        }
    }
}

// MARK: - AVPlayerWrapper Extension
extension AVPlayerWrapper {
    public func generateThumbnail(at time: Double, completion: @escaping (UIImage?) -> Void) {
        guard let generator = thumbnailGenerator else {
            print("AVPlayerWrapper: No asset available for thumbnail generation.")
            completion(nil)
            return
        }
        
        generator.generateThumbnail(at: time, completion: completion)
    }
}
