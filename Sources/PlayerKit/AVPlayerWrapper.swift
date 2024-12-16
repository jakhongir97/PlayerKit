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
extension AVPlayerWrapper: TrackSelectionProtocol {
    public var availableAudioTracks: [TrackInfo] {
        guard let asset = player?.currentItem?.asset,
              let audioGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return [] }
        return audioGroup.options.map { option in
            let id = option.extendedLanguageTag ?? option.locale?.identifier ?? UUID().uuidString
            let name = option.displayName
            let languageCode = option.extendedLanguageTag ?? option.locale?.languageCode
            return TrackInfo(id: id, name: name, languageCode: languageCode)
        }
    }
    
    public var availableSubtitles: [TrackInfo] {
        guard let asset = player?.currentItem?.asset,
              let subtitleGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return [] }
        return subtitleGroup.options.map { option in
            let id = option.extendedLanguageTag ?? option.locale?.identifier ?? UUID().uuidString
            let name = option.displayName
            let languageCode = option.extendedLanguageTag ?? option.locale?.languageCode
            return TrackInfo(id: id, name: name, languageCode: languageCode)
        }
    }
    
    public var currentAudioTrack: TrackInfo? {
        guard let asset = player?.currentItem?.asset,
              let audioGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .audible),
              let selectedOption = player?.currentItem?.selectedMediaOption(in: audioGroup) else { return nil }
        let id = selectedOption.extendedLanguageTag ?? selectedOption.locale?.identifier ?? UUID().uuidString
        let name = selectedOption.displayName
        let languageCode = selectedOption.extendedLanguageTag ?? selectedOption.locale?.languageCode
        return TrackInfo(id: id, name: name, languageCode: languageCode)
    }
    
    public var currentSubtitleTrack: TrackInfo? {
        guard let asset = player?.currentItem?.asset,
              let subtitleGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .legible),
              let selectedOption = player?.currentItem?.selectedMediaOption(in: subtitleGroup) else { return nil }
        let id = selectedOption.extendedLanguageTag ?? selectedOption.locale?.identifier ?? UUID().uuidString
        let name = selectedOption.displayName
        let languageCode = selectedOption.extendedLanguageTag ?? selectedOption.locale?.languageCode
        return TrackInfo(id: id, name: name, languageCode: languageCode)
    }
    
    public func selectAudioTrack(withID id: String) {
        guard let asset = player?.currentItem?.asset,
              let audioGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .audible),
              let option = audioGroup.options.first(where: {
                  $0.extendedLanguageTag == id ||
                  $0.locale?.identifier == id
              }) else { return }
        player?.currentItem?.select(option, in: audioGroup)
    }
    
    public func selectSubtitle(withID id: String?) {
        guard let asset = player?.currentItem?.asset,
              let subtitleGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return }
        if let id = id,
           let option = subtitleGroup.options.first(where: {
               $0.extendedLanguageTag == id ||
               $0.locale?.identifier == id
           }) {
            player?.currentItem?.select(option, in: subtitleGroup)
        } else {
            player?.currentItem?.select(nil, in: subtitleGroup)
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
        
        // Observe the player item's status
        playerItemStatusObserver = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self = self else { return }
            if item.status == .readyToPlay {
                // Tracks are now available; refresh track info
                DispatchQueue.main.async {
                    PlayerManager.shared.isMediaReady = true
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
        }
        
        let newPlayerView = AVPlayerView()
        newPlayerView.player = player
        playerView = newPlayerView
        setupPiP()
        return newPlayerView
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

// MARK: - StreamingInfoProtocol
extension AVPlayerWrapper: StreamingInfoProtocol {
    public func fetchStreamingInfo() -> StreamingInfo {
        guard let playerItem = player?.currentItem else {
            return StreamingInfo.placeholder
        }
        
        // Extract Buffer Duration as String
        let bufferDuration = formatBufferDuration(for: playerItem)
        
        // Extract Bitrate as String (if multiple bitrates are available, choose the first)
        let videoBitrate = extractVideoBitrate(from: playerItem)
        
        // Extract Resolution
        let resolution = extractResolution(from: playerItem)
        
        // Extract Frame Rate
        let frameRate = extractFrameRate(from: playerItem)
        
        return StreamingInfo(
            frameRate: frameRate,
            videoBitrate: videoBitrate,
            resolution: resolution,
            bufferDuration: bufferDuration
        )
    }
    
    // MARK: - Helper Methods
    private func formatBufferDuration(for playerItem: AVPlayerItem) -> String {
        guard let timeRange = playerItem.loadedTimeRanges.first?.timeRangeValue else {
            return "0 sec"
        }
        let duration = CMTimeGetSeconds(timeRange.start) + CMTimeGetSeconds(timeRange.duration)
        let intDuration = Int(duration.rounded())
        return "\(intDuration) sec"
    }
    
    private func extractVideoBitrate(from playerItem: AVPlayerItem) -> String {
        let accessLogEvents = playerItem.accessLog()?.events ?? []
        // Choose the first indicated bitrate if available
        if let firstEvent = accessLogEvents.first {
            let mbps = firstEvent.indicatedBitrate / 1_000_000
            if mbps > 0 {
                return String(format: "%.2f Mbps", mbps)
            }
        }
        return "0 Mbps"
    }
    
    private func extractResolution(from playerItem: AVPlayerItem) -> String {
        let size = playerItem.presentationSize
        return size.width > 0 && size.height > 0
        ? "\(Int(size.width))x\(Int(size.height))"
        : "Unknown"
    }
    
    private func extractFrameRate(from playerItem: AVPlayerItem) -> String {
        guard let videoTrack = playerItem.tracks.first?.currentVideoFrameRate else { return "Unknown" }
        return "\(Int(videoTrack)) fps"
    }
}
