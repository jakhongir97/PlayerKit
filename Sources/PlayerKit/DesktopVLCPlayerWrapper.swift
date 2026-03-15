#if os(macOS) && !canImport(VLCKit)
import AppKit
import Darwin
import Foundation

private enum DesktopVLCState: Int32 {
    case nothingSpecial = 0
    case opening = 1
    case buffering = 2
    case playing = 3
    case paused = 4
    case stopped = 5
    case ended = 6
    case error = 7
}

private enum DesktopVLCPaths {
    static let libDirectory = "/Applications/VLC.app/Contents/MacOS/lib"
    static let pluginsDirectory = "/Applications/VLC.app/Contents/MacOS/plugins"
    static let libvlcPath = "\(libDirectory)/libvlc.dylib"
    static let libvlcCorePath = "\(libDirectory)/libvlccore.dylib"

    static var isInstalled: Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: libvlcPath)
            && fileManager.fileExists(atPath: libvlcCorePath)
            && fileManager.fileExists(atPath: pluginsDirectory)
    }
}

private struct DesktopVLCTrackDescription {
    var identifier: Int32
    var name: UnsafeMutablePointer<CChar>?
    var next: UnsafeMutablePointer<DesktopVLCTrackDescription>?
}

private final class DesktopVLCLibrary {
    typealias VLCInstancePointer = OpaquePointer
    typealias VLCMediaPointer = OpaquePointer
    typealias VLCMediaPlayerPointer = OpaquePointer

    private typealias LibVLCNew = @convention(c) (Int32, UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> VLCInstancePointer?
    private typealias LibVLCRelease = @convention(c) (VLCInstancePointer?) -> Void
    private typealias LibVLCMediaNewLocation = @convention(c) (VLCInstancePointer?, UnsafePointer<CChar>?) -> VLCMediaPointer?
    private typealias LibVLCMediaRelease = @convention(c) (VLCMediaPointer?) -> Void
    private typealias LibVLCMediaPlayerNewFromMedia = @convention(c) (VLCMediaPointer?) -> VLCMediaPlayerPointer?
    private typealias LibVLCMediaPlayerRelease = @convention(c) (VLCMediaPlayerPointer?) -> Void
    private typealias LibVLCMediaPlayerSetNSObject = @convention(c) (VLCMediaPlayerPointer?, UnsafeMutableRawPointer?) -> Void
    private typealias LibVLCMediaPlayerPlay = @convention(c) (VLCMediaPlayerPointer?) -> Int32
    private typealias LibVLCMediaPlayerPause = @convention(c) (VLCMediaPlayerPointer?) -> Void
    private typealias LibVLCMediaPlayerStop = @convention(c) (VLCMediaPlayerPointer?) -> Void
    private typealias LibVLCMediaPlayerGetTime = @convention(c) (VLCMediaPlayerPointer?) -> Int64
    private typealias LibVLCMediaPlayerSetTime = @convention(c) (VLCMediaPlayerPointer?, Int64) -> Void
    private typealias LibVLCMediaPlayerGetLength = @convention(c) (VLCMediaPlayerPointer?) -> Int64
    private typealias LibVLCMediaPlayerGetPosition = @convention(c) (VLCMediaPlayerPointer?) -> Float
    private typealias LibVLCMediaPlayerIsPlaying = @convention(c) (VLCMediaPlayerPointer?) -> Int32
    private typealias LibVLCMediaPlayerGetState = @convention(c) (VLCMediaPlayerPointer?) -> Int32
    private typealias LibVLCMediaPlayerGetRate = @convention(c) (VLCMediaPlayerPointer?) -> Float
    private typealias LibVLCMediaPlayerSetRate = @convention(c) (VLCMediaPlayerPointer?, Float) -> Int32
    private typealias LibVLCAudioSetMute = @convention(c) (VLCMediaPlayerPointer?, Int32) -> Void
    private typealias LibVLCAudioGetTrack = @convention(c) (VLCMediaPlayerPointer?) -> Int32
    private typealias LibVLCAudioSetTrack = @convention(c) (VLCMediaPlayerPointer?, Int32) -> Int32
    private typealias LibVLCAudioGetTrackDescription = @convention(c) (VLCMediaPlayerPointer?) -> UnsafeMutableRawPointer?
    private typealias LibVLCVideoGetSPU = @convention(c) (VLCMediaPlayerPointer?) -> Int32
    private typealias LibVLCVideoSetSPU = @convention(c) (VLCMediaPlayerPointer?, Int32) -> Int32
    private typealias LibVLCVideoGetSPUDescription = @convention(c) (VLCMediaPlayerPointer?) -> UnsafeMutableRawPointer?
    private typealias LibVLCTrackDescriptionListRelease = @convention(c) (UnsafeMutableRawPointer?) -> Void

    static let shared = DesktopVLCLibrary()
    static var isAvailable: Bool { shared.available }

    private let available: Bool
    private let coreHandle: UnsafeMutableRawPointer?
    private let vlcHandle: UnsafeMutableRawPointer?

    private let newInstanceFn: LibVLCNew?
    private let releaseInstanceFn: LibVLCRelease?
    private let newMediaFn: LibVLCMediaNewLocation?
    private let releaseMediaFn: LibVLCMediaRelease?
    private let newPlayerFn: LibVLCMediaPlayerNewFromMedia?
    private let releasePlayerFn: LibVLCMediaPlayerRelease?
    private let setNSObjectFn: LibVLCMediaPlayerSetNSObject?
    private let playFn: LibVLCMediaPlayerPlay?
    private let pauseFn: LibVLCMediaPlayerPause?
    private let stopFn: LibVLCMediaPlayerStop?
    private let getTimeFn: LibVLCMediaPlayerGetTime?
    private let setTimeFn: LibVLCMediaPlayerSetTime?
    private let getLengthFn: LibVLCMediaPlayerGetLength?
    private let getPositionFn: LibVLCMediaPlayerGetPosition?
    private let isPlayingFn: LibVLCMediaPlayerIsPlaying?
    private let getStateFn: LibVLCMediaPlayerGetState?
    private let getRateFn: LibVLCMediaPlayerGetRate?
    private let setRateFn: LibVLCMediaPlayerSetRate?
    private let audioSetMuteFn: LibVLCAudioSetMute?
    private let audioGetTrackFn: LibVLCAudioGetTrack?
    private let audioSetTrackFn: LibVLCAudioSetTrack?
    private let audioGetTrackDescriptionFn: LibVLCAudioGetTrackDescription?
    private let videoGetSPUFn: LibVLCVideoGetSPU?
    private let videoSetSPUFn: LibVLCVideoSetSPU?
    private let videoGetSPUDescriptionFn: LibVLCVideoGetSPUDescription?
    private let releaseTrackDescriptionFn: LibVLCTrackDescriptionListRelease?

    private init() {
        guard DesktopVLCPaths.isInstalled else {
            available = false
            coreHandle = nil
            vlcHandle = nil
            newInstanceFn = nil
            releaseInstanceFn = nil
            newMediaFn = nil
            releaseMediaFn = nil
            newPlayerFn = nil
            releasePlayerFn = nil
            setNSObjectFn = nil
            playFn = nil
            pauseFn = nil
            stopFn = nil
            getTimeFn = nil
            setTimeFn = nil
            getLengthFn = nil
            getPositionFn = nil
            isPlayingFn = nil
            getStateFn = nil
            getRateFn = nil
            setRateFn = nil
            audioSetMuteFn = nil
            audioGetTrackFn = nil
            audioSetTrackFn = nil
            audioGetTrackDescriptionFn = nil
            videoGetSPUFn = nil
            videoSetSPUFn = nil
            videoGetSPUDescriptionFn = nil
            releaseTrackDescriptionFn = nil
            return
        }

        setenv("VLC_PLUGIN_PATH", DesktopVLCPaths.pluginsDirectory, 1)

        let coreHandle = dlopen(DesktopVLCPaths.libvlcCorePath, RTLD_NOW | RTLD_GLOBAL)
        let vlcHandle = dlopen(DesktopVLCPaths.libvlcPath, RTLD_NOW | RTLD_GLOBAL)

        self.coreHandle = coreHandle
        self.vlcHandle = vlcHandle

        newInstanceFn = Self.loadSymbol(vlcHandle, "libvlc_new", as: LibVLCNew.self)
        releaseInstanceFn = Self.loadSymbol(vlcHandle, "libvlc_release", as: LibVLCRelease.self)
        newMediaFn = Self.loadSymbol(vlcHandle, "libvlc_media_new_location", as: LibVLCMediaNewLocation.self)
        releaseMediaFn = Self.loadSymbol(vlcHandle, "libvlc_media_release", as: LibVLCMediaRelease.self)
        newPlayerFn = Self.loadSymbol(vlcHandle, "libvlc_media_player_new_from_media", as: LibVLCMediaPlayerNewFromMedia.self)
        releasePlayerFn = Self.loadSymbol(vlcHandle, "libvlc_media_player_release", as: LibVLCMediaPlayerRelease.self)
        setNSObjectFn = Self.loadSymbol(vlcHandle, "libvlc_media_player_set_nsobject", as: LibVLCMediaPlayerSetNSObject.self)
        playFn = Self.loadSymbol(vlcHandle, "libvlc_media_player_play", as: LibVLCMediaPlayerPlay.self)
        pauseFn = Self.loadSymbol(vlcHandle, "libvlc_media_player_pause", as: LibVLCMediaPlayerPause.self)
        stopFn = Self.loadSymbol(vlcHandle, "libvlc_media_player_stop", as: LibVLCMediaPlayerStop.self)
        getTimeFn = Self.loadSymbol(vlcHandle, "libvlc_media_player_get_time", as: LibVLCMediaPlayerGetTime.self)
        setTimeFn = Self.loadSymbol(vlcHandle, "libvlc_media_player_set_time", as: LibVLCMediaPlayerSetTime.self)
        getLengthFn = Self.loadSymbol(vlcHandle, "libvlc_media_player_get_length", as: LibVLCMediaPlayerGetLength.self)
        getPositionFn = Self.loadSymbol(vlcHandle, "libvlc_media_player_get_position", as: LibVLCMediaPlayerGetPosition.self)
        isPlayingFn = Self.loadSymbol(vlcHandle, "libvlc_media_player_is_playing", as: LibVLCMediaPlayerIsPlaying.self)
        getStateFn = Self.loadSymbol(vlcHandle, "libvlc_media_player_get_state", as: LibVLCMediaPlayerGetState.self)
        getRateFn = Self.loadSymbol(vlcHandle, "libvlc_media_player_get_rate", as: LibVLCMediaPlayerGetRate.self)
        setRateFn = Self.loadSymbol(vlcHandle, "libvlc_media_player_set_rate", as: LibVLCMediaPlayerSetRate.self)
        audioSetMuteFn = Self.loadSymbol(vlcHandle, "libvlc_audio_set_mute", as: LibVLCAudioSetMute.self)
        audioGetTrackFn = Self.loadSymbol(vlcHandle, "libvlc_audio_get_track", as: LibVLCAudioGetTrack.self)
        audioSetTrackFn = Self.loadSymbol(vlcHandle, "libvlc_audio_set_track", as: LibVLCAudioSetTrack.self)
        audioGetTrackDescriptionFn = Self.loadSymbol(vlcHandle, "libvlc_audio_get_track_description", as: LibVLCAudioGetTrackDescription.self)
        videoGetSPUFn = Self.loadSymbol(vlcHandle, "libvlc_video_get_spu", as: LibVLCVideoGetSPU.self)
        videoSetSPUFn = Self.loadSymbol(vlcHandle, "libvlc_video_set_spu", as: LibVLCVideoSetSPU.self)
        videoGetSPUDescriptionFn = Self.loadSymbol(vlcHandle, "libvlc_video_get_spu_description", as: LibVLCVideoGetSPUDescription.self)
        releaseTrackDescriptionFn = Self.loadSymbol(vlcHandle, "libvlc_track_description_list_release", as: LibVLCTrackDescriptionListRelease.self)

        available =
            coreHandle != nil &&
            vlcHandle != nil &&
            newInstanceFn != nil &&
            releaseInstanceFn != nil &&
            newMediaFn != nil &&
            releaseMediaFn != nil &&
            newPlayerFn != nil &&
            releasePlayerFn != nil &&
            setNSObjectFn != nil &&
            playFn != nil &&
            pauseFn != nil &&
            stopFn != nil &&
            getTimeFn != nil &&
            setTimeFn != nil &&
            getLengthFn != nil &&
            getPositionFn != nil &&
            isPlayingFn != nil &&
            getStateFn != nil &&
            getRateFn != nil &&
            setRateFn != nil &&
            audioSetMuteFn != nil
    }

    deinit {
        if let vlcHandle {
            dlclose(vlcHandle)
        }
        if let coreHandle {
            dlclose(coreHandle)
        }
    }

    private static func loadSymbol<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(symbol, to: type)
    }

    func makeInstance() -> VLCInstancePointer? {
        guard available, let newInstanceFn else { return nil }
        return newInstanceFn(0, nil)
    }

    func releaseInstance(_ instance: VLCInstancePointer?) {
        guard instance != nil else { return }
        releaseInstanceFn?(instance)
    }

    func makePlayer(instance: VLCInstancePointer?, url: URL, drawable: NSView) -> VLCMediaPlayerPointer? {
        guard available, let instance, let newMediaFn, let releaseMediaFn, let newPlayerFn else { return nil }
        let media = url.absoluteString.withCString { newMediaFn(instance, $0) }
        guard let media else { return nil }
        defer { releaseMediaFn(media) }
        guard let player = newPlayerFn(media) else { return nil }
        setNSObjectFn?(player, Unmanaged.passUnretained(drawable).toOpaque())
        return player
    }

    func releasePlayer(_ player: VLCMediaPlayerPointer?) {
        guard player != nil else { return }
        releasePlayerFn?(player)
    }

    func play(_ player: VLCMediaPlayerPointer?) {
        guard player != nil else { return }
        _ = playFn?(player)
    }

    func pause(_ player: VLCMediaPlayerPointer?) {
        guard player != nil else { return }
        pauseFn?(player)
    }

    func stop(_ player: VLCMediaPlayerPointer?) {
        guard player != nil else { return }
        stopFn?(player)
    }

    func currentTime(for player: VLCMediaPlayerPointer?) -> Double {
        guard let player, let getTimeFn else { return 0 }
        return Double(getTimeFn(player)) / 1000
    }

    func duration(for player: VLCMediaPlayerPointer?) -> Double {
        guard let player, let getLengthFn else { return 0 }
        return Double(getLengthFn(player)) / 1000
    }

    func bufferedPosition(for player: VLCMediaPlayerPointer?) -> Double {
        guard let player, let getPositionFn else { return 0 }
        return Double(getPositionFn(player))
    }

    func isPlaying(_ player: VLCMediaPlayerPointer?) -> Bool {
        guard let player, let isPlayingFn else { return false }
        return isPlayingFn(player) != 0
    }

    func state(for player: VLCMediaPlayerPointer?) -> DesktopVLCState {
        guard let player, let getStateFn, let state = DesktopVLCState(rawValue: getStateFn(player)) else {
            return .nothingSpecial
        }
        return state
    }

    func rate(for player: VLCMediaPlayerPointer?) -> Float {
        guard let player, let getRateFn else { return 1 }
        return getRateFn(player)
    }

    func setRate(_ rate: Float, for player: VLCMediaPlayerPointer?) {
        guard let player else { return }
        _ = setRateFn?(player, rate)
    }

    func setMuted(_ muted: Bool, for player: VLCMediaPlayerPointer?) {
        guard player != nil else { return }
        audioSetMuteFn?(player, muted ? 1 : 0)
    }

    func seek(to seconds: Double, for player: VLCMediaPlayerPointer?) -> Bool {
        guard let player, let setTimeFn else { return false }
        setTimeFn(player, Int64(seconds * 1000))
        return true
    }

    func availableAudioTracks(for player: VLCMediaPlayerPointer?) -> [TrackInfo] {
        guard let player else { return [] }
        return trackInfos(
            currentID: audioGetTrackFn?(player),
            descriptions: audioGetTrackDescriptionFn?(player)
        )
    }

    func availableSubtitleTracks(for player: VLCMediaPlayerPointer?) -> [TrackInfo] {
        guard let player else { return [] }
        return trackInfos(
            currentID: videoGetSPUFn?(player),
            descriptions: videoGetSPUDescriptionFn?(player)
        )
    }

    func currentAudioTrackID(for player: VLCMediaPlayerPointer?) -> String? {
        guard let player, let audioGetTrackFn else { return nil }
        let id = audioGetTrackFn(player)
        return id >= 0 ? String(id) : nil
    }

    func currentSubtitleTrackID(for player: VLCMediaPlayerPointer?) -> String? {
        guard let player, let videoGetSPUFn else { return nil }
        let id = videoGetSPUFn(player)
        return id >= 0 ? String(id) : nil
    }

    func selectAudioTrack(_ identifier: String, for player: VLCMediaPlayerPointer?) {
        guard let player, let audioSetTrackFn, let id = Int32(identifier) else { return }
        _ = audioSetTrackFn(player, id)
    }

    func selectSubtitleTrack(_ identifier: String?, for player: VLCMediaPlayerPointer?) {
        guard let player, let videoSetSPUFn else { return }
        let id = identifier.flatMap(Int32.init) ?? -1
        _ = videoSetSPUFn(player, id)
    }

    private func trackInfos(
        currentID: Int32?,
        descriptions: UnsafeMutableRawPointer?
    ) -> [TrackInfo] {
        defer { releaseTrackDescriptionFn?(descriptions) }

        var infos: [TrackInfo] = []
        var current = descriptions?.assumingMemoryBound(to: DesktopVLCTrackDescription.self)
        while let currentPointer = current {
            let description = currentPointer.pointee
            let id = String(description.identifier)
            let name = description.name.flatMap { String(validatingUTF8: $0) } ?? id
            if description.identifier >= 0 {
                infos.append(TrackInfo(id: id, name: name, languageCode: nil))
            }
            current = description.next
        }

        if let currentID, currentID >= 0, infos.contains(where: { $0.id == String(currentID) }) == false {
            infos.append(TrackInfo(id: String(currentID), name: String(currentID), languageCode: nil))
        }

        return infos
    }
}

public final class DesktopVLCPlayerWrapper: NSObject, PlayerProtocol {
    private let runtime = DesktopVLCLibrary.shared
    private let playerView = VLCPlayerView()

    private var instance: DesktopVLCLibrary.VLCInstancePointer?
    private var mediaPlayer: DesktopVLCLibrary.VLCMediaPlayerPointer?
    private var pollTimer: Timer?
    private var pendingResumeTime: Double?
    private var hasReportedReady = false
    private var lastState: DesktopVLCState = .nothingSpecial
    private var shouldEmitRuntimeState = false

    weak var lifecycleReporter: PlayerLifecycleReporting?
    var onRuntimeStateChange: ((PlayerRuntimeState) -> Void)?

    public override init() {
        super.init()
    }

    deinit {
        stopPolling()
        releasePlayer()
        runtime.releaseInstance(instance)
    }

    private var state: DesktopVLCState {
        runtime.state(for: mediaPlayer)
    }

    private func ensureInstance() -> Bool {
        if instance == nil {
            instance = runtime.makeInstance()
        }
        return instance != nil
    }

    private func releasePlayer() {
        runtime.releasePlayer(mediaPlayer)
        mediaPlayer = nil
    }

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.pollPlayer()
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollPlayer() {
        guard mediaPlayer != nil else { return }

        if !hasReportedReady, duration > 0 || state == .playing || state == .paused {
            hasReportedReady = true
            lifecycleReporter?.playerDidBecomeReady()
            lifecycleReporter?.playerDidUpdateTracks()

            if let pendingResumeTime {
                _ = runtime.seek(to: pendingResumeTime, for: mediaPlayer)
                self.pendingResumeTime = nil
            }
        }

        let currentState = state
        if currentState != lastState {
            handleStateTransition(from: lastState, to: currentState)
            lastState = currentState
        }

        emitRuntimeState()
    }

    private func handleStateTransition(from previous: DesktopVLCState, to current: DesktopVLCState) {
        switch current {
        case .buffering:
            lifecycleReporter?.playerDidStall()
        case .ended:
            lifecycleReporter?.playerDidEndPlayback()
        case .error:
            lifecycleReporter?.playerDidFail(with: .mediaLoadFailed("libvlc playback failed"))
        case .stopped where previous == .playing || previous == .buffering:
            lifecycleReporter?.playerDidEndPlayback()
        default:
            break
        }
    }

    private func emitRuntimeState() {
        guard shouldEmitRuntimeState else { return }
        onRuntimeStateChange?(
            PlayerRuntimeState(
                isPlaying: isPlaying,
                isBuffering: isBuffering,
                currentTime: currentTime,
                duration: duration,
                bufferedDuration: bufferedDuration
            )
        )
    }
}

extension DesktopVLCPlayerWrapper: PlaybackControlProtocol {
    public var isPlaying: Bool {
        runtime.isPlaying(mediaPlayer)
    }

    public var playbackSpeed: Float {
        get { runtime.rate(for: mediaPlayer) }
        set { runtime.setRate(newValue, for: mediaPlayer) }
    }

    public func play() {
        runtime.play(mediaPlayer)
        startPolling()
        emitRuntimeState()
    }

    public func pause() {
        runtime.pause(mediaPlayer)
        emitRuntimeState()
    }

    public func stop() {
        runtime.stop(mediaPlayer)
        emitRuntimeState()
    }

    public func setMuted(_ muted: Bool) {
        runtime.setMuted(muted, for: mediaPlayer)
    }
}

extension DesktopVLCPlayerWrapper: TimeControlProtocol {
    public var currentTime: Double {
        runtime.currentTime(for: mediaPlayer)
    }

    public var duration: Double {
        runtime.duration(for: mediaPlayer)
    }

    public var bufferedDuration: Double {
        duration * runtime.bufferedPosition(for: mediaPlayer)
    }

    public var isBuffering: Bool {
        state == .opening || state == .buffering
    }

    public func seek(to time: Double, completion: ((Bool) -> Void)? = nil) {
        guard duration > 0 else {
            completion?(false)
            return
        }
        let success = runtime.seek(to: time, for: mediaPlayer)
        completion?(success)
        emitRuntimeState()
    }

    public func scrubForward(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    public func scrubBackward(by seconds: TimeInterval) {
        seek(to: max(0, currentTime - seconds))
    }
}

extension DesktopVLCPlayerWrapper: TrackSelectionProtocol {
    public var availableAudioTracks: [TrackInfo] {
        runtime.availableAudioTracks(for: mediaPlayer)
    }

    public var availableSubtitles: [TrackInfo] {
        runtime.availableSubtitleTracks(for: mediaPlayer)
    }

    public var currentAudioTrack: TrackInfo? {
        let tracks = runtime.availableAudioTracks(for: mediaPlayer)
        return tracks.first { $0.id == runtime.currentAudioTrackID(for: mediaPlayer) }
    }

    public var currentSubtitleTrack: TrackInfo? {
        let tracks = runtime.availableSubtitleTracks(for: mediaPlayer)
        return tracks.first { $0.id == runtime.currentSubtitleTrackID(for: mediaPlayer) }
    }

    public func selectAudioTrack(withID id: String) {
        runtime.selectAudioTrack(id, for: mediaPlayer)
        lifecycleReporter?.playerDidUpdateTracks()
    }

    public func selectSubtitle(withID id: String?) {
        runtime.selectSubtitleTrack(id, for: mediaPlayer)
        lifecycleReporter?.playerDidUpdateTracks()
    }
}

extension DesktopVLCPlayerWrapper: MediaLoadingProtocol {
    public func load(url: URL, lastPosition: Double? = nil) {
        guard DesktopVLCLibrary.isAvailable, ensureInstance() else {
            lifecycleReporter?.playerDidFail(with: .mediaLoadFailed("Desktop VLC is unavailable"))
            return
        }

        stopPolling()
        releasePlayer()

        pendingResumeTime = lastPosition
        hasReportedReady = false
        lastState = .nothingSpecial

        mediaPlayer = runtime.makePlayer(instance: instance, url: url, drawable: playerView)
        guard mediaPlayer != nil else {
            lifecycleReporter?.playerDidFail(with: .mediaLoadFailed("Failed to create desktop VLC player"))
            return
        }

        startPolling()
        runtime.play(mediaPlayer)
        emitRuntimeState()
    }
}

extension DesktopVLCPlayerWrapper: ViewRenderingProtocol {
    public func getPlayerView() -> PKView {
        playerView
    }

    public func setupPiP() {}
    public func startPiP() {}
    public func stopPiP() {}
}

extension DesktopVLCPlayerWrapper: GestureHandlingProtocol {
    public func handlePinchGesture(scale: CGFloat) {
        scale > 1 ? setGravityToFill() : setGravityToDefault()
    }

    public func setGravityToDefault() {}
    public func setGravityToFill() {}
}

extension DesktopVLCPlayerWrapper: StreamingInfoProtocol {
    public func fetchStreamingInfo() -> StreamingInfo {
        .placeholder
    }
}

extension DesktopVLCPlayerWrapper: PlayerEventSource {}
extension DesktopVLCPlayerWrapper: PlayerMuteControlling {}

extension DesktopVLCPlayerWrapper: PlayerPictureInPictureSupporting {
    var isPictureInPictureSupported: Bool { false }
    var isPictureInPicturePossible: Bool { false }
}

extension DesktopVLCPlayerWrapper: PlayerStateSource {
    func startRuntimeStateUpdates() {
        shouldEmitRuntimeState = true
        emitRuntimeState()
    }

    func stopRuntimeStateUpdates() {
        shouldEmitRuntimeState = false
    }
}
#endif
