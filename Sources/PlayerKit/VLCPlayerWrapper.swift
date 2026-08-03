#if canImport(VLCKit) && !os(macOS)
import Foundation
import VLCKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private enum VLCMediaPlayerEvent: Sendable {
    case stopped
    case buffering
    case error
    case other
}

private final class VLCMediaPlayerDelegateProxy: NSObject, VLCMediaPlayerDelegate {
    weak var wrapper: VLCPlayerWrapper?
    let generation: UInt64

    init(wrapper: VLCPlayerWrapper, generation: UInt64) {
        self.wrapper = wrapper
        self.generation = generation
    }

    nonisolated func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        let event: VLCMediaPlayerEvent
        switch newState {
        case .stopped: event = .stopped
        case .buffering: event = .buffering
        case .error: event = .error
        default: event = .other
        }
        let target = wrapper
        let callbackGeneration = generation
        Task { @MainActor in
            target?.handleMediaPlayerEvent(event, generation: callbackGeneration)
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        let target = wrapper
        let callbackGeneration = generation
        Task { @MainActor in
            target?.handleMediaPlayerTimeChanged(generation: callbackGeneration)
        }
    }
}

private final class VLCMediaDelegateProxy: NSObject, VLCMediaDelegate {
    weak var wrapper: VLCPlayerWrapper?
    let generation: UInt64

    init(wrapper: VLCPlayerWrapper, generation: UInt64) {
        self.wrapper = wrapper
        self.generation = generation
    }

    nonisolated func mediaDidFinishParsing(_ aMedia: VLCMedia) {
        let target = wrapper
        let callbackGeneration = generation
        Task { @MainActor in
            target?.handleMediaDidFinishParsing(generation: callbackGeneration)
        }
    }

    nonisolated func mediaMetaDataDidChange(_ aMedia: VLCMedia) {
        let target = wrapper
        let callbackGeneration = generation
        Task { @MainActor in
            target?.handleMediaMetadataDidChange(generation: callbackGeneration)
        }
    }
}

@MainActor
public class VLCPlayerWrapper: NSObject, PlayerProtocol {
    public internal(set) var player: VLCMediaPlayer
    private let playerView = VLCPlayerView()
    #if canImport(UIKit)
    public var pipController: VLCPictureInPictureWindowControlling? {
        didSet {
            if let oldValue,
               pipController == nil || oldValue !== pipController {
                oldValue.stateChangeEventHandler = nil
                oldValue.stopPictureInPicture()
            }
            pipController?.stateChangeEventHandler = { [weak self] isStarted in
                Task { @MainActor [weak self] in
                    self?.lifecycleReporter?.playerDidChangePiPState(isActive: isStarted)
                }
            }
        }
    }
    private var drawableProxy: VLCPlayerDrawableProxy?
    #endif
    private var lastPosition: Double?
    private var shouldEmitRuntimeState = false
    /// Survives media replacement, unlike `VLCMediaPlayer.rate`.
    private var desiredPlaybackRate: Float = 1.0
    private var desiredMuted = false
    private var mediaGeneration: UInt64 = 0
    private var playerDelegateProxy: VLCMediaPlayerDelegateProxy?
    private var mediaDelegateProxy: VLCMediaDelegateProxy?
    /// Cancels a pending resume-position application if the media changes first.
    private var pendingResumeGeneration = 0
    /// Distinguishes a caller-requested stop from reaching the end of the media,
    /// both of which VLCKit surfaces as `.stopped`.
    private var isStoppingByRequest = false
    
    public weak var lifecycleReporter: PlayerLifecycleReporting?
    public var onRuntimeStateChange: ((PlayerRuntimeState) -> Void)?
    public var hasLoadedMedia: Bool { player.media != nil }
    
    public override init() {
        self.player = VLCMediaPlayer()
        super.init()

        configurePlayer(player, generation: mediaGeneration)
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

    private func configurePlayer(_ player: VLCMediaPlayer, generation: UInt64) {
        #if canImport(UIKit)
        if drawableProxy == nil {
            drawableProxy = VLCPlayerDrawableProxy(wrapper: self)
        }
        player.drawable = drawableProxy
        #else
        player.drawable = playerView
        #endif
        let proxy = VLCMediaPlayerDelegateProxy(wrapper: self, generation: generation)
        playerDelegateProxy = proxy
        player.delegate = proxy
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
            guard newValue.isFinite, newValue > 0 else { return }
            desiredPlaybackRate = newValue
            player.rate = newValue
        }
    }

    public func play() {
        player.play()
        // Re-assert the selected rate: it does not survive media replacement.
        player.rate = desiredPlaybackRate
        player.audio?.isMuted = desiredMuted
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
        desiredMuted = muted
        player.audio?.isMuted = muted
    }
}

// MARK: - TimeControlProtocol
extension VLCPlayerWrapper: TimeControlProtocol {
    public var currentTime: Double {
        let value = Double(player.time.intValue) / 1000
        return value.isFinite ? max(value, 0) : 0
    }
    
    public var duration: Double {
        let value = Double(player.media?.length.intValue ?? 0) / 1000
        return value.isFinite ? max(value, 0) : 0
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

    public func seek(to time: Double, completion: (@MainActor (Bool) -> Void)? = nil) {
        guard time.isFinite, time >= 0, duration > 0 else {
            completion?(false)
            return
        }

        let vlcTime = VLCTime(number: NSNumber(value: time * 1000))
        player.time = vlcTime

        // VLCKit's time setter is asynchronous and reports no result, so this
        // cannot honestly claim success. Verify that the playhead actually
        // landed near the requested time instead of fabricating `true`.
        let tolerance = 1.0
        let generation = mediaGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    completion?(false)
                    return
                }
                guard self.mediaGeneration == generation else {
                    completion?(false)
                    return
                }
                let landed = abs(self.currentTime - time) <= tolerance
                completion?(landed)
                self.emitRuntimeState()
            }
        }
    }
    
    public func scrubForward(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }
    
    public func scrubBackward(by seconds: TimeInterval) {
        guard seconds.isFinite else { return }
        seek(to: max(currentTime - seconds, 0))
    }
}

extension VLCPlayerWrapper: PlayerMuteControlling {}

extension VLCPlayerWrapper: PlayerVolumeControlling {
    /// VLCKit's scale is 0…200, where 100 is unity and anything above it
    /// amplifies. PlayerKit deliberately stops at unity: a gesture that can
    /// clip the signal is not a volume control, it is a distortion pedal.
    public var outputVolume: Float {
        guard let audio = player.audio else { return 1 }
        return min(max(Float(audio.volume) / 100, 0), 1)
    }

    public func setOutputVolume(_ value: Float) {
        guard value.isFinite else { return }
        player.audio?.volume = Int32((min(max(value, 0), 1) * 100).rounded())
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
        mediaGeneration &+= 1
        pendingResumeGeneration &+= 1
        isStoppingByRequest = false
        let oldPlayer = player
        oldPlayer.delegate = nil
        oldPlayer.media?.delegate = nil
        mediaDelegateProxy = nil
        oldPlayer.stop()

        let replacement = VLCMediaPlayer()
        player = replacement
        configurePlayer(replacement, generation: mediaGeneration)
        #if canImport(UIKit)
        pipController = nil
        #endif

        let media = VLCMedia(url: url)
        self.lastPosition = lastPosition.flatMap { value in
            value.isFinite && value >= 0 ? value : nil
        }
        player.media = media
        let mediaProxy = VLCMediaDelegateProxy(wrapper: self, generation: mediaGeneration)
        mediaDelegateProxy = mediaProxy
        player.media?.delegate = mediaProxy
        player.play()
        player.rate = desiredPlaybackRate
        player.audio?.isMuted = desiredMuted
        emitRuntimeState()
    }
}

// MARK: - VLCMediaDelegate relay handlers
extension VLCPlayerWrapper {
    fileprivate func handleMediaDidFinishParsing(generation: UInt64) {
        guard mediaGeneration == generation, player.media != nil else { return }
        lifecycleReporter?.playerDidBecomeReady()
        emitRuntimeState()

        guard let position = lastPosition else { return }
        // Applying the resume position is still delayed — VLCKit will not
        // accept a seek until it has started decoding — but it is tied to the
        // generation that requested it so stale callbacks cannot seek new media.
        pendingResumeGeneration += 1
        let resumeGeneration = pendingResumeGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self,
                  self.mediaGeneration == generation,
                  self.pendingResumeGeneration == resumeGeneration,
                  self.player.media != nil else { return }
            self.player.time = VLCTime(number: NSNumber(value: position * 1000))
            self.lastPosition = nil
            self.emitRuntimeState()
        }
    }
    
    fileprivate func handleMediaMetadataDidChange(generation: UInt64) {
        guard mediaGeneration == generation, player.media != nil else { return }
        lifecycleReporter?.playerDidUpdateTracks()
    }
}

// MARK: - VLCMediaPlayer Notification Handlers
extension VLCPlayerWrapper {
    /// VLCKit delivers these on its own thread. Every branch hops to main
    /// because they all end up mutating `@Published` state on `PlayerManager`;
    /// previously the `else` branch and `mediaPlayerTimeChanged` did not, which
    /// is undefined behaviour for SwiftUI observation.
    fileprivate func handleMediaPlayerEvent(
        _ event: VLCMediaPlayerEvent,
        generation: UInt64
    ) {
        guard mediaGeneration == generation else { return }
        switch event {
        case .stopped:
            // VLCKit reports both "reached the end of the media" and "was
            // told to stop" as `.stopped`. Only the former is end-of-playback;
            // reporting the latter would fire autoplay-next when the host
            // deliberately tore the player down.
            if isStoppingByRequest {
                isStoppingByRequest = false
            } else {
                lifecycleReporter?.playerDidEndPlayback()
            }
        case .buffering:
            lifecycleReporter?.playerDidStall()
        case .error:
            lifecycleReporter?.playerDidFail(with: .mediaLoadFailed("VLC playback error"))
        case .other:
            break
        }
        emitRuntimeState()
    }

    fileprivate func handleMediaPlayerTimeChanged(generation: UInt64) {
        guard mediaGeneration == generation else { return }
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
    public var isZoomSupported: Bool {
        #if canImport(UIKit)
        if let orientation = playerView.window?.windowScene?.interfaceOrientation,
           orientation != .unknown {
            return orientation.isLandscape
        }
        #endif
        return !PlayerKitPlatform.isPortraitInterface
    }

    public func handlePinchGesture(scale: CGFloat) {
        guard isZoomSupported else { return }
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
extension VLCPlayerWrapper: PlayerMediaAvailabilityReporting {}


extension VLCPlayerWrapper: PlayerPictureInPictureSupporting {
    public var isPictureInPictureSupported: Bool {
        #if canImport(UIKit)
        true
        #else
        false
        #endif
    }

    public var isPictureInPicturePossible: Bool {
        #if canImport(UIKit)
        pipController != nil
        #else
        false
        #endif
    }
}

extension VLCPlayerWrapper: PlayerStateSource {
    public func startRuntimeStateUpdates() {
        shouldEmitRuntimeState = true
        emitRuntimeState()
    }
    
    public func stopRuntimeStateUpdates() {
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
