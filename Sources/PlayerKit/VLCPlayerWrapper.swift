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
    /// Survives media replacement, unlike `VLCMediaPlayer.rate`.
    private var desiredPlaybackRate: Float = 1.0
    /// Cancels a pending resume-position application if the media changes first.
    private var pendingResumeGeneration = 0
    /// Distinguishes a caller-requested stop from reaching the end of the media,
    /// both of which VLCKit surfaces as `.stopped`.
    private var isStoppingByRequest = false
    
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
    
    /// Enables VLCKit's console logger. Opt-in: never call this in release
    /// builds, it is extremely verbose.
    ///
    /// (Previously defined but never called; kept behind the same compile-time
    /// flag as the rest of PlayerKit's logging so it cannot be switched on by
    /// accident.)
    func setupLogging() {
        #if PLAYERKIT_DEBUG_LOGGING
        let logger = VLCConsoleLogger()
        logger.level = .debug
        logger.formatter.contextFlags = .levelContextModule
        player.libraryInstance.loggers = [logger]
        #endif
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
        PlayerKitLog.debug("VLCPlayerWrapper", "deinit")
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
    
    /// Held separately from `player.rate`, which VLCKit resets to 1× whenever
    /// new media is set — silently discarding the user's speed selection on
    /// every load and every episode change.
    public var playbackSpeed: Float {
        get { desiredPlaybackRate }
        set {
            let sanitized = (newValue.isFinite && newValue > 0) ? newValue : 1.0
            desiredPlaybackRate = sanitized
            player.rate = sanitized
        }
    }

    public func play() {
        player.play()
        // Re-assert the selected rate: it does not survive media replacement.
        player.rate = desiredPlaybackRate
        emitRuntimeState()
    }
    
    public func pause() {
        player.pause()
        emitRuntimeState()
    }
    
    public func stop() {
        isStoppingByRequest = true
        pendingResumeGeneration += 1
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
    
    /// VLCKit exposes no buffered-range API, so this is genuinely unknown.
    ///
    /// It previously returned `duration * player.position` — but `position` is
    /// the *playback* position as a 0...1 fraction, so this evaluated to
    /// `currentTime`. That drove the buffer indicator with the playhead, which
    /// is not merely useless but actively misleading. Reporting 0 says "no
    /// information" honestly rather than asserting something false.
    public var bufferedDuration: Double {
        return 0
    }

    public var isBuffering: Bool {
        // `.buffering` and `isPlaying` are not mutually exclusive in VLCKit —
        // requiring both used to make mid-playback rebuffering invisible while
        // the desktop backend reported it. Match the desktop backend.
        return player.state == .buffering || player.state == .opening
    }

    public func seek(to time: Double, completion: ((Bool) -> Void)? = nil) {
        guard duration > 0 else {
            completion?(false)
            return
        }

        let vlcTime = VLCTime(number: NSNumber(value: time * 1000))
        player.time = vlcTime

        // VLCKit's time setter is asynchronous and reports no result, so this
        // cannot honestly claim success. Verify that the playhead actually
        // landed near the requested time instead of fabricating `true`.
        let tolerance = 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else {
                completion?(false)
                return
            }
            let landed = abs(self.currentTime - time) <= tolerance
            completion?(landed)
            self.emitRuntimeState()
        }
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
    /// Track identity for the VLC backend.
    ///
    /// `trackName` alone was used as both the identifier and the basis of the
    /// display name. That is wrong twice over: names are not unique (two
    /// "English" tracks collide, so selecting one picks the other), and
    /// `split(separator:" ").dropFirst()` produced an *empty* display name for
    /// any single-word track name. The index makes the identifier unique and
    /// the full name is kept for display.
    private static func trackIdentifier(index: Int, name: String) -> String {
        "\(index)|\(name)"
    }

    private static func trackIndex(fromIdentifier identifier: String) -> Int? {
        guard let separator = identifier.firstIndex(of: "|") else { return nil }
        return Int(identifier[identifier.startIndex ..< separator])
    }

    private func trackInfo(index: Int, name: String, language: String?) -> TrackInfo {
        TrackInfo(
            id: Self.trackIdentifier(index: index, name: name),
            name: name,
            languageCode: language
        )
    }

    public var availableAudioTracks: [TrackInfo] {
        player.audioTracks.enumerated().map { index, track in
            trackInfo(index: index, name: track.trackName, language: track.language)
        }
    }

    public var availableSubtitles: [TrackInfo] {
        player.textTracks.enumerated().map { index, track in
            trackInfo(index: index, name: track.trackName, language: track.language)
        }
    }

    public var currentAudioTrack: TrackInfo? {
        guard let index = player.audioTracks.firstIndex(where: { $0.isSelected }) else { return nil }
        let track = player.audioTracks[index]
        return trackInfo(index: index, name: track.trackName, language: track.language)
    }

    public var currentSubtitleTrack: TrackInfo? {
        guard let index = player.textTracks.firstIndex(where: { $0.isSelected }) else { return nil }
        let track = player.textTracks[index]
        return trackInfo(index: index, name: track.trackName, language: track.language)
    }

    public func selectAudioTrack(withID id: String) {
        let tracks = player.audioTracks
        guard let index = Self.trackIndex(fromIdentifier: id), tracks.indices.contains(index) else {
            return
        }
        tracks[index].isSelectedExclusively = true
    }

    public func selectSubtitle(withID id: String?) {
        guard let id else {
            player.deselectAllTextTracks()
            return
        }
        let tracks = player.textTracks
        guard let index = Self.trackIndex(fromIdentifier: id), tracks.indices.contains(index) else {
            player.deselectAllTextTracks()
            return
        }
        tracks[index].isSelectedExclusively = true
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
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lifecycleReporter?.playerDidBecomeReady()
            self.emitRuntimeState()

            guard let position = self.lastPosition else { return }
            // Applying the resume position is still delayed — VLCKit will not
            // accept a seek until it has started decoding — but it is now tied
            // to the media that requested it. Previously an unconditional
            // asyncAfter would fire after the media had been replaced, or after
            // the user had already scrubbed somewhere else, and clobber them.
            self.pendingResumeGeneration += 1
            let generation = self.pendingResumeGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self,
                      self.pendingResumeGeneration == generation,
                      self.player.media === aMedia else { return }
                self.player.time = VLCTime(number: NSNumber(value: position * 1000))
                self.lastPosition = nil
                self.emitRuntimeState()
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
    /// VLCKit delivers these on its own thread. Every branch hops to main
    /// because they all end up mutating `@Published` state on `PlayerManager`;
    /// previously the `else` branch and `mediaPlayerTimeChanged` did not, which
    /// is undefined behaviour for SwiftUI observation.
    public func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch newState {
            case .stopped:
                // VLCKit reports both "reached the end of the media" and "was
                // told to stop" as `.stopped`. Only the former is end-of-playback;
                // reporting the latter would fire autoplay-next when the host
                // deliberately tore the player down.
                if self.isStoppingByRequest {
                    self.isStoppingByRequest = false
                } else {
                    self.lifecycleReporter?.playerDidEndPlayback()
                }
            case .buffering:
                self.lifecycleReporter?.playerDidStall()
            case .error:
                self.lifecycleReporter?.playerDidFail(with: .mediaLoadFailed("VLC playback error"))
            default:
                break
            }
            self.emitRuntimeState()
        }
    }

    public func mediaPlayerTimeChanged(_ aNotification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.emitRuntimeState()
        }
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
