#if canImport(VLCKit)
import Foundation
import VLCKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public class VLCPlayerWrapper: NSObject, PlayerProtocol {
    public var player: VLCMediaPlayer
    private let playerView = VLCPlayerView()
    #if canImport(UIKit)
    public var pipController: VLCPictureInPictureWindowControlling?
    private var drawableProxy: VLCPlayerDrawableProxy?
    #endif
    private var lastPosition: Double?
    private var shouldEmitRuntimeState = false
    
    weak var lifecycleReporter: PlayerLifecycleReporting?
    var onRuntimeStateChange: ((PlayerRuntimeState) -> Void)?
    
    public override init() {
        self.player = VLCMediaPlayer()
        super.init()

        #if canImport(UIKit)
        drawableProxy = VLCPlayerDrawableProxy(wrapper: self)
        player.drawable = drawableProxy
        #else
        player.drawable = playerView
        #endif

        player.delegate = self
        setupObservers()
    }
    
    func setupLogging() {
        let logger = VLCConsoleLogger()
        logger.level = .debug
        logger.formatter.contextFlags = .levelContextModule
        player.libraryInstance.loggers = [logger]
    }
    
    func setupObservers() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDeviceLock), name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
        #endif
    }
    
    #if canImport(UIKit)
    @objc private func handleDeviceLock() {
        player.pause()
    }
    #endif
    
    deinit {
        print("VLCPlayerWrapper deinit")
        #if canImport(UIKit)
        NotificationCenter.default.removeObserver(self, name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
        #endif
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
        emitRuntimeState()
    }
    
    public func pause() {
        player.pause()
        emitRuntimeState()
    }
    
    public func stop() {
        player.stop()
        emitRuntimeState()
    }

    public func setMuted(_ muted: Bool) {
        player.audio?.isMuted = muted
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
        
        let vlcTime = VLCTime(number: NSNumber(value: time * 1000))
        player.time = vlcTime
        
        completion?(true)
        emitRuntimeState()
    }
    
    public func scrubForward(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }
    
    public func scrubBackward(by seconds: TimeInterval) {
        seek(to: currentTime - seconds)
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
            track.isSelectedExclusively = true
        }
    }
    
    public func selectSubtitle(withID id: String?) {
        if let id = id, let track = player.textTracks.first(where: { $0.trackName == id }) {
            track.isSelectedExclusively = true
        } else {
            player.deselectAllTextTracks()
        }
    }
}

// MARK: - MediaLoadingProtocol
extension VLCPlayerWrapper: MediaLoadingProtocol {
    public func load(url: URL, lastPosition: Double? = nil) {
        let media = VLCMedia(url: url)
        self.lastPosition = lastPosition
        player.media = media
        player.media?.delegate = self
        player.play()
        emitRuntimeState()
    }
}

// MARK: - VLCMediaDelegate
extension VLCPlayerWrapper: VLCMediaDelegate {
    public func mediaDidFinishParsing(_ aMedia: VLCMedia) {
        DispatchQueue.main.async {
            self.lifecycleReporter?.playerDidBecomeReady()
            self.emitRuntimeState()
        }
        if let position = lastPosition {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.player.time = VLCTime(number: NSNumber(value: position * 1000))
                self?.emitRuntimeState()
            }
        }
    }
    
    public func mediaMetaDataDidChange(_ aMedia: VLCMedia) {
        DispatchQueue.main.async {
            self.lifecycleReporter?.playerDidUpdateTracks()
        }
    }
}

// MARK: - VLCMediaPlayer Notification Handlers
extension VLCPlayerWrapper: VLCMediaPlayerDelegate {
    public func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        if newState == .stopped {
            DispatchQueue.main.async {
                self.lifecycleReporter?.playerDidEndPlayback()
                self.emitRuntimeState()
            }
        } else if newState == .buffering {
            DispatchQueue.main.async {
                self.lifecycleReporter?.playerDidStall()
                self.emitRuntimeState()
            }
        } else if newState == .error {
            DispatchQueue.main.async {
                self.lifecycleReporter?.playerDidFail(with: .mediaLoadFailed("VLC playback error"))
                self.emitRuntimeState()
            }
        } else {
            emitRuntimeState()
        }
    }
    
    public func mediaPlayerTimeChanged(_ aNotification: Notification) {
        emitRuntimeState()
    }
}


// MARK: - ViewRenderingProtocol
extension VLCPlayerWrapper: ViewRenderingProtocol {
    public func getPlayerView() -> PKView {
        return playerView
    }
    
    public func setupPiP() {}
    
    public func startPiP() {
        #if canImport(UIKit)
        pipController?.startPictureInPicture()
        #endif
    }
    
    public func stopPiP() {
        #if canImport(UIKit)
        pipController?.stopPictureInPicture()
        #endif
    }
}

// MARK: - GestureHandlingProtocol
extension VLCPlayerWrapper: GestureHandlingProtocol {
    public func handlePinchGesture(scale: CGFloat) {
        guard !PlayerKitPlatform.isPortraitInterface else { return }
        scale > 1 ? setGravityToFill() : setGravityToDefault()
    }
    
    public func setGravityToDefault() {
        guard player.videoAspectRatio != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.player.videoAspectRatio = nil
        }
    }
    
    public func setGravityToFill() {
        DispatchQueue.main.async { [weak self] in
            self?.player.videoAspectRatio = self?.currentAspectRatio()
        }
    }
    
    private func currentAspectRatio() -> String {
        let bounds = playerView.bounds
        let width = Int(bounds.width)
        let height = Int(bounds.height)
        if width > 0, height > 0 {
            return "\(width):\(height)"
        }
        return "16:9"
    }
}

// MARK: - StreamingInfoProtocol
extension VLCPlayerWrapper: StreamingInfoProtocol {
    public func fetchStreamingInfo() -> StreamingInfo {
        guard let media = player.media else {
            return .placeholder
        }
        
        let tracksInfo = media.tracksInformation
        let resolution = extractCurrentResolution()
        let frameRate = extractFrameRate(from: tracksInfo)
        let videoBitrate = extractVideoBitrate(from: media)
        
        return StreamingInfo(
            frameRate: frameRate,
            videoBitrate: videoBitrate,
            resolution: resolution,
            bufferDuration: "0 sec"
        )
    }
    
    // MARK: - Helper Methods
    private func extractCurrentResolution() -> String {
        let videoSize = player.videoSize
        let width = Int(videoSize.width)
        let height = Int(videoSize.height)
        
        if width > 0 && height > 0 {
            return "\(width)x\(height)"
        }
        return "Unknown"
    }
    
    private func extractFrameRate(from tracks: [VLCMedia.Track]) -> String {
        for track in tracks {
            if track.type == .video, let videoTrack = track.video {
                let frameRate = videoTrack.frameRate
                let frameRateDenominator = videoTrack.frameRateDenominator
                if frameRate > 0, frameRateDenominator > 0 {
                    let fps = Double(frameRate) / Double(frameRateDenominator)
                    let roundedFps = Int(ceil(fps))
                    return "\(roundedFps) fps"
                }
            }
        }
        return "Unknown"
    }
    
    private func extractVideoBitrate(from media: VLCMedia) -> String {
        let bitrate = media.statistics.demuxBitrate
        let bitrateMbps = Double(bitrate)
        return String(format: "%.2f Mbps", bitrateMbps)
    }
    
}

extension VLCPlayerWrapper: PlayerEventSource {}

extension VLCPlayerWrapper: PlayerMuteControlling {}

extension VLCPlayerWrapper: PlayerPictureInPictureSupporting {
    var isPictureInPictureSupported: Bool {
        #if canImport(UIKit)
        true
        #else
        false
        #endif
    }

    var isPictureInPicturePossible: Bool {
        #if canImport(UIKit)
        pipController != nil
        #else
        false
        #endif
    }
}

extension VLCPlayerWrapper: PlayerStateSource {
    func startRuntimeStateUpdates() {
        shouldEmitRuntimeState = true
        emitRuntimeState()
    }
    
    func stopRuntimeStateUpdates() {
        shouldEmitRuntimeState = false
    }
}

extension VLCPlayerWrapper {
    private func emitRuntimeState() {
        guard shouldEmitRuntimeState else { return }
        let state = PlayerRuntimeState(
            isPlaying: isPlaying,
            isBuffering: isBuffering,
            currentTime: currentTime,
            duration: duration,
            bufferedDuration: bufferedDuration
        )
        onRuntimeStateChange?(state)
    }
}
#elseif os(macOS)
public typealias VLCPlayerWrapper = DesktopVLCPlayerWrapper
#else
public typealias VLCPlayerWrapper = AVPlayerWrapper
#endif
