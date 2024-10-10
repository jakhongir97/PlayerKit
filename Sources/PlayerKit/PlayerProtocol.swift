import Foundation

public protocol PlayerProtocol: AnyObject {
    var isPlaying: Bool { get }
    var currentTime: Double { get }
    var duration: Double { get }
    var isBuffering: Bool { get }

    var availableAudioTracks: [String] { get }
    var availableSubtitles: [String] { get }

    func play()
    func pause()
    func stop()
    func load(url: URL)
    func seek(to time: Double)
    func selectAudioTrack(index: Int)
    func selectSubtitle(index: Int)
}
