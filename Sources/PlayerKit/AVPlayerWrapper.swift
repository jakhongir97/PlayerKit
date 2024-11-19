import AVKit
import UIKit

public class AVPlayerWrapper: NSObject, PlayerProtocol {
    public var player: AVPlayer?
    private var playerView: AVPlayerView?
    private var pipController: AVPictureInPictureController?
    
    private var playerItemStatusObserver: NSKeyValueObservation?
    private var playbackEndedObserver: Any?
    
    // Lazy initialization for thumbnail generator
    private lazy var thumbnailGenerator: AVPlayerThumbnailGenerator? = {
        guard let asset = player?.currentItem?.asset else { return nil }
        return AVPlayerThumbnailGenerator(asset: asset)
    }()
    
    // MARK: - Initializer
    public override init() {
        super.init()
    }
    
    deinit {
        // Remove observers to prevent memory leaks
        playerItemStatusObserver = nil
        if let observer = playbackEndedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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
}

// MARK: - MediaLoadingProtocol
extension AVPlayerWrapper: MediaLoadingProtocol {
    public func load(url: URL, lastPosition: Double? = nil) {
        let playerItem = AVPlayerItem(url: url)
        if let player = player {
            player.replaceCurrentItem(with: playerItem)
        } else {
            player = AVPlayer(playerItem: playerItem)
            player?.allowsExternalPlayback = true
        }
        player?.allowsExternalPlayback = true
        
        // Observe the player item's status
        playerItemStatusObserver = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self = self else { return }
            if item.status == .readyToPlay {
                // Tracks are now available; refresh track info
                DispatchQueue.main.async {
                    PlayerManager.shared.refreshTrackInfo()
                }
            }
        }
        
        // Observe when playback ends
        playbackEndedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            // Notify PlayerManager that playback ended
            PlayerManager.shared.videoDidEnd()
        }
        
        // Seek to last position if provided, else start from the beginning
        if let position = lastPosition {
            let targetTime = CMTime(seconds: position, preferredTimescale: 600)
            player?.seek(to: targetTime)
        }
        
        player?.play()
    }
}

// MARK: - ViewRenderingProtocol
extension AVPlayerWrapper: ViewRenderingProtocol {
    public func getPlayerView() -> UIView {
        if let playerView = playerView {
            return playerView
        } else {
            let newPlayerView = AVPlayerView()
            newPlayerView.player = player
            playerView = newPlayerView
            setupPiP()
            return newPlayerView
        }
    }
    
    public func setupPiP() {
        guard let playerLayer = playerView?.playerLayer else {
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
        guard let playerLayer = playerView?.playerLayer else { return }
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
