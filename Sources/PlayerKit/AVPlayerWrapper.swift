import AVKit
import UIKit

public class AVPlayerWrapper: NSObject, PlayerProtocol {
    public var player: AVPlayer?
    private var playerView: AVPlayerView?
    private var pipController: AVPictureInPictureController?
    
    // Lazy initialization for thumbnail generator
    private lazy var thumbnailGenerator: AVPlayerThumbnailGenerator? = {
        guard let asset = player?.currentItem?.asset else { return nil }
        return AVPlayerThumbnailGenerator(asset: asset)
    }()
    
    // MARK: - Initializer
    public override init() {
        super.init()
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
        player?.play()
    }
    
    public func pause() {
        player?.pause()
    }
    
    public func stop() {
        player?.pause()
        player?.seek(to: .zero)
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
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            completion?(finished)
        }
    }
}

// MARK: - TrackSelectionProtocol
// AVPlayerWrapper.swift
extension AVPlayerWrapper: TrackSelectionProtocol {
    public var availableAudioTracks: [String] {
        guard let asset = player?.currentItem?.asset,
              let audioGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return [] }
        return audioGroup.options.map { $0.displayName }
    }

    public var availableSubtitles: [String] {
        guard let asset = player?.currentItem?.asset,
              let subtitleGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return [] }
        return subtitleGroup.options.map { $0.displayName }
    }

    public var availableVideoTracks: [String] {
        guard let asset = player?.currentItem?.asset,
              let videoGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .visual) else { return [] }
        return videoGroup.options.map { $0.displayName }
    }

    public var currentAudioTrack: String? {
        guard let asset = player?.currentItem?.asset,
              let audioGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return nil }

        let selectedOption = player?.currentItem?.selectedMediaOption(in: audioGroup)
        return selectedOption?.displayName
    }
    
    public var currentSubtitleTrack: String? {
        guard let asset = player?.currentItem?.asset,
              let subtitleGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return nil }

        let selectedOption = player?.currentItem?.selectedMediaOption(in: subtitleGroup)
        return selectedOption?.displayName
    }
    
    public var currentVideoTrack: String? {
        guard let asset = player?.currentItem?.asset,
              let videoGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .visual) else { return nil }
        
        let selectedOption = player?.currentItem?.selectedMediaOption(in: videoGroup)
        return selectedOption?.displayName
    }

    public func selectAudioTrack(index: Int) {
        guard let audioGroup = player?.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .audible),
              index < audioGroup.options.count else { return }
        player?.currentItem?.select(audioGroup.options[index], in: audioGroup)
    }

    public func selectSubtitle(index: Int?) {
        guard let subtitleGroup = player?.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return }
        
        if let index = index, index < subtitleGroup.options.count {
            player?.currentItem?.select(subtitleGroup.options[index], in: subtitleGroup)
        } else {
            player?.currentItem?.select(nil, in: subtitleGroup) // Deselects all subtitles
        }
    }

    public func selectVideoTrack(index: Int) {
        guard let videoGroup = player?.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .visual),
              index < videoGroup.options.count else { return }
        player?.currentItem?.select(videoGroup.options[index], in: videoGroup)
    }
}

// MARK: - MediaLoadingProtocol
extension AVPlayerWrapper: MediaLoadingProtocol {
    public func load(url: URL) {
        player = AVPlayer(url: url)
        player?.allowsExternalPlayback = true
        playerView?.player = player
    }
}

// MARK: - ViewRenderingProtocol
extension AVPlayerWrapper: ViewRenderingProtocol {
    public func getPlayerView() -> UIView {
        if let existingView = playerView {
            return existingView
        }
        
        let newPlayerView = AVPlayerView()
        newPlayerView.player = player
        playerView = newPlayerView
        return newPlayerView
    }
    
    public func setupPiP() {
        guard let playerView = getPlayerView() as? AVPlayerView, let playerLayer = playerView.playerLayer else {
            print("AVPlayerWrapper: No playerLayer available for PiP.")
            return
        }
        pipController = AVPictureInPictureController(playerLayer: playerLayer)
        pipController?.delegate = self
    }
    
    public func startPiP() {
        if AVPictureInPictureController.isPictureInPictureSupported() {
            pipController?.startPictureInPicture()
        } else {
            print("PiP is not supported on this device.")
        }
    }
    
    public func stopPiP() {
        pipController?.stopPictureInPicture()
    }
}

// MARK: - ThumbnailGeneratorProtocol
extension AVPlayerWrapper: ThumbnailGeneratorProtocol {
    public func generateThumbnail(at time: Double, completion: @escaping (UIImage?) -> Void) {
        guard let generator = thumbnailGenerator else {
            print("AVPlayerWrapper: No asset available for thumbnail generation.")
            completion(nil)
            return
        }
        
        generator.generateThumbnail(at: time, completion: completion)
    }
}

// MARK: - GestureHandlingProtocol
extension AVPlayerWrapper: GestureHandlingProtocol {
    public func handlePinchGesture(scale: CGFloat) {
        guard let playerView = getPlayerView() as? AVPlayerView, let playerLayer = playerView.playerLayer else { return }
        playerLayer.videoGravity = scale > 1 ? .resizeAspectFill : .resizeAspect
    }
}

// MARK: - AVPictureInPictureControllerDelegate
extension AVPlayerWrapper: AVPictureInPictureControllerDelegate {
    public func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        PlayerManager.shared.isPiPActive = true
    }
    
    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        PlayerManager.shared.isPiPActive = false
    }
}
