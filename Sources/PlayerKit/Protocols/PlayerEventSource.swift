import Foundation

struct PlayerRuntimeState {
    let isPlaying: Bool
    let isBuffering: Bool
    let currentTime: Double
    let duration: Double
    let bufferedDuration: Double
}

protocol PlayerLifecycleReporting: AnyObject {
    func playerDidBecomeReady()
    func playerDidUpdateTracks()
    func playerDidEndPlayback()
    func playerDidChangePiPState(isActive: Bool)
    func playerDidStall()
    func playerDidFail(with error: PlayerKitError)
}

protocol PlayerEventSource: AnyObject {
    var lifecycleReporter: PlayerLifecycleReporting? { get set }
}

protocol PlayerStateSource: AnyObject {
    var onRuntimeStateChange: ((PlayerRuntimeState) -> Void)? { get set }
    func startRuntimeStateUpdates()
    func stopRuntimeStateUpdates()
}
