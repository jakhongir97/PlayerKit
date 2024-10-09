import Foundation

public protocol PlayerProtocol: AnyObject {
    func play()
    func pause()
    func stop()
    func load(url: URL)
    var isPlaying: Bool { get }
    var currentTime: Double { get }
    var duration: Double { get }
    
    var availableAudioTracks: [String] { get }
    var availableSubtitles: [String] { get }
    
    func selectAudioTrack(index: Int)
    func selectSubtitle(index: Int)
}



